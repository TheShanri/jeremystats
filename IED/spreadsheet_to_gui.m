function spreadsheet_to_gui(excelPath, dataMatPath, varargin)
% spreadsheet_to_gui
% Creates a lightweight GUI to manually click and save anchor points for
% events defined in a spreadsheet.
%
% USAGE:
%   spreadsheet_to_gui("events.xlsx", "data.mat")
%   spreadsheet_to_gui("events.xlsx", "data.mat", 'channelIndices', 1:32, 'winHalfWidthMs', 1000)

% ---------- 1. Input Parsing ----------
p = inputParser;
p.addRequired('excelPath', @(s) isstring(s) || ischar(s));
p.addRequired('dataMatPath', @(s) isstring(s) || ischar(s));
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('scaleToMicroV', 1, @(x)isnumeric(x) && all(isfinite(x)) && all(x>0));
p.addParameter('winHalfWidthMs', 1000, @(x)isfinite(x)&&x>0); % Default: ±1 second window

p.parse(excelPath, dataMatPath, varargin{:});
excelPath    = string(p.Results.excelPath);
dataMatPath  = string(p.Results.dataMatPath);
channelIdx   = p.Results.channelIndices;
scaleToMicroV= p.Results.scaleToMicroV;
winHWms      = p.Results.winHalfWidthMs;

fprintf('===== spreadsheet_to_gui =====\n');

% ---------- 2. Setup IO & Data ----------
assert(isfile(excelPath), 'Excel file not found: %s', excelPath);
assert(isfile(dataMatPath), 'Data MAT file not found: %s', dataMatPath);

fprintf('Loading matfile (fast)... ');
mf = matfile(dataMatPath);
try
    sfx = mf.sfx;
catch
    error('Missing "sfx" (sampling frequency) in data MAT file.');
end
nRowsAll = size(mf, 'd', 1);
nSamp    = size(mf, 'd', 2);
try
    kept_channels = mf.kept_channels;
catch
    kept_channels = [];
end
fprintf('Done.\n');

% ---------- 3. Channel & Scaling Setup ----------
if isempty(channelIdx)
    chList = 1:nRowsAll;
else
    chList = channelIdx(:).';
    chList = chList(chList >= 1 & chList <= nRowsAll);
end
nCh = numel(chList);
assert(nCh > 0, 'No valid channels selected.');

chanLabels = get_channel_labels(chList, kept_channels);

if numel(scaleToMicroV) == 1
    scaleVec = repmat(scaleToMicroV, nRowsAll, 1);
else
    assert(numel(scaleToMicroV) >= nRowsAll, 'scaleToMicroV must be scalar or length >= nRowsAll.');
    scaleVec = scaleToMicroV(:);
end

% ---------- 4. Windowing Setup ----------
HWwin    = max(1, round(winHWms    * sfx));  % ±plot half-width
tRelMs   = (-HWwin:HWwin) / sfx * 1e3;
winN     = numel(tRelMs); %#ok<NASGU>

% ---------- 5. Read Excel File ----------
fprintf('Reading event stamps... ');
T_events = readtable(excelPath, 'ReadVariableNames', true);
[onSamp, offSamp] = find_event_stamps(T_events, sfx);
T_events.onsamp = onSamp;
T_events.offsamp = offSamp;
numEvents = height(T_events);
assert(numEvents > 0, 'No event data found in Excel file.');
fprintf('Found %d events.\n', numEvents);

% ---------- 6. Prepare Results Table ----------
Results = T_events;
Results.manual_anchor_samp = nan(numEvents, 1);

% ---------- 7. Create GUI ----------
fprintf('Building GUI... ');
fig = uifigure('Name', 'Spreadsheet-to-GUI Anchor Tool', ...
               'Position', [100 100 1200 800], ...
               'UserData', [], ...
               'CloseRequestFcn', @(src,evt) closeGUI(src));

% Main grid layout
gl = uigridlayout(fig, [10, 4]);
gl.RowHeight = {'1x', 'fit', 'fit'};
gl.ColumnWidth = {'1x', '1x', '1x', '1x'};
gl.RowHeight(1:7) = {'1x'};
gl.RowHeight(8) = {'2x'}; % Make plot area large
gl.RowHeight(9) = {'fit'};
gl.RowHeight(10) = {30};

% Plotting area
ax = uiaxes(gl);
ax.Layout.Row = [1 8];
ax.Layout.Column = [1 4];
ax.YTick = [];
ax.YTickLabel = [];
ax.XTick = [];
ax.XTickLabel = [];
box(ax, 'on');

% Status label
statusLabel = uilabel(gl, 'Text', 'Loading...', ...
                      'FontSize', 14, 'FontWeight', 'bold', ...
                      'HorizontalAlignment', 'center');
statusLabel.Layout.Row = 9;
statusLabel.Layout.Column = [1 4];

% Buttons
prevButton = uibutton(gl, 'Text', '<< Prev Event', ...
                    'ButtonPushedFcn', @(src,evt) prevClicked(fig));
prevButton.Layout.Row = 10;
prevButton.Layout.Column = 1;

skipButton = uibutton(gl, 'Text', 'Skip Event >>', ...
                    'ButtonPushedFcn', @(src,evt) skipClicked(fig), ...
                    'FontColor', [0.8 0 0]);
skipButton.Layout.Row = 10;
skipButton.Layout.Column = 2;

nextButton = uibutton(gl, 'Text', 'Next Event >>', ...
                    'ButtonPushedFcn', @(src,evt) nextClicked(fig));
nextButton.Layout.Row = 10;
nextButton.Layout.Column = 3;

saveButton = uibutton(gl, 'Text', 'Finish & Save CSV', ...
                    'ButtonPushedFcn', @(src,evt) saveClicked(fig), ...
                    'BackgroundColor', [0.1 0.7 0.1], 'FontColor', 'w');
saveButton.Layout.Row = 10;
saveButton.Layout.Column = 4;

% ---------- 8. Store State in UserData ----------
ud = struct();
ud.mf = mf;
ud.sfx = sfx;
ud.nSamp = nSamp;
ud.T_events = T_events;
ud.Results = Results;
ud.CurrentIndex = 1;
ud.chList = chList;
ud.nCh = nCh;
ud.chanLabels = chanLabels;
ud.scaleVec = scaleVec;
ud.HWwin = HWwin;
ud.tRelMs = tRelMs;
ud.ax = ax;
ud.statusLabel = statusLabel;
ud.PlotHandles = {};      % Cell array for line handles
ud.MidpointLine = [];   % Handle for the midpoint xline
ud.AnchorLine = [];     % Handle for the selected anchor xline
ud.AxesTiles = {};        % Handles to the individual axes tiles

fig.UserData = ud;

% ---------- 9. Initial Plot ----------
updatePlot(fig);
fprintf('GUI is ready. Please select anchor points.\n');

end

% ======================================================================
%                          GUI HELPER FUNCTIONS
% ======================================================================

function updatePlot(fig)
    ud = fig.UserData;
    idx = ud.CurrentIndex;
    
    % --- Get event info ---
    onsamp = ud.T_events.onsamp(idx);
    offsamp = ud.T_events.offsamp(idx);
    mid = round((onsamp + offsamp) / 2);
    
    % --- Define plot window ---
    s0 = mid - ud.HWwin;
    s1 = mid + ud.HWwin;
    
    % --- Check for out-of-bounds ---
    if s0 < 1 || s1 > ud.nSamp
        cla(ud.ax); % Clear the main axes
        text(ud.ax, 0.5, 0.5, sprintf('Event %d: Plot window is out of bounds.\nData may be corrupt or window is too large.', idx), ...
            'HorizontalAlignment', 'center', 'Color', 'r', 'FontSize', 14);
        ud.statusLabel.Text = sprintf('Event %d of %d (OUT OF BOUNDS)', idx, height(ud.T_events));
        return;
    end
    
    tRelMs_Mid = (mid - mid) / ud.sfx * 1e3; % This is 0
    
    % --- Plotting ---
    if isempty(ud.PlotHandles)
        % --- First time: Create all axes and plot objects ---
        cla(ud.ax); % Clear the 'loading' text
        tl = tiledlayout(ud.ax, ud.nCh, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
        ud.AxesTiles = cell(ud.nCh, 1);
        ud.PlotHandles = cell(ud.nCh, 1);
        
        for k = 1:ud.nCh
            ax_k = nexttile(tl);
            ch = ud.chList(k);
            sc = ud.scaleVec(ch);
            y = double(ud.mf.d(ch, s0:s1)) * sc;
            
            h = plot(ax_k, ud.tRelMs, y, 'Color', [0.1 0.1 0.8]);
            
            hold(ax_k, 'on');
            grid(ax_k, 'on');
            box(ax_k, 'on');
            xlim(ax_k, [ud.tRelMs(1), ud.tRelMs(end)]);
            ylabel(ax_k, '\muV');
            title(ax_k, ud.chanLabels{k}, 'FontSize', 9, 'FontWeight', 'normal');
            set(ax_k, 'FontSize', 8);
            if k < ud.nCh
                set(ax_k, 'XTickLabel', []); % Remove x-labels
            end
            
            % Set the click callback for this specific tile
            ax_k.ButtonDownFcn = @(src,evt) recordClick(fig, evt);
            
            ud.PlotHandles{k} = h;
            ud.AxesTiles{k} = ax_k;
        end
        xlabel(ax_k, 'Time relative to Midpoint (ms)');
        
        % Create persistent visual guide lines
        ud.MidpointLine = xline(ud.AxesTiles{1}, tRelMs_Mid, '--k', 'Midpoint', 'LineWidth', 1.5, 'HandleVisibility', 'off');
        ud.AnchorLine   = xline(ud.AxesTiles{1}, NaN, '-r', 'Anchor', 'LineWidth', 2.0, 'HandleVisibility', 'off');
        % Link all axes to share the lines
        linkaxes([ud.AxesTiles{:}], 'x');
        
    else
        % --- Subsequent times: Just update YData (FAST) ---
        for k = 1:ud.nCh
            ch = ud.chList(k);
            sc = ud.scaleVec(ch);
            y = double(ud.mf.d(ch, s0:s1)) * sc;
            set(ud.PlotHandles{k}, 'YData', y);
        end
        
        % Reset x-axis limits (in case of zoom/pan)
        xlim(ud.AxesTiles{1}, [ud.tRelMs(1), ud.tRelMs(end)]);
    end
    
    % --- Update Visual Guides ---
    set(ud.MidpointLine, 'Value', tRelMs_Mid); % This is always 0
    
    selected_anchor_samp = ud.Results.manual_anchor_samp(idx);
    if isfinite(selected_anchor_samp)
        tRelMs_Anchor = (selected_anchor_samp - mid) / ud.sfx * 1e3;
        set(ud.AnchorLine, 'Value', tRelMs_Anchor, 'Visible', 'on');
    else
        set(ud.AnchorLine, 'Visible', 'off');
    end
    
    % --- Update Status ---
    ud.statusLabel.Text = sprintf('Event %d of %d (Excel Row: %d)', idx, height(ud.T_events), idx);
    
    % Save state
    fig.UserData = ud;
    drawnow('limitrate');
end

% ======================================================================
%                        GUI CALLBACK FUNCTIONS
% ======================================================================

function recordClick(fig, evt)
    ud = fig.UserData;
    idx = ud.CurrentIndex;

    % --- 1. Get click info ---
    clicked_time_ms = evt.IntersectionPoint(1); % Time (ms) relative to midpoint
    
    % --- 2. Get event midpoint sample ---
    onsamp = ud.T_events.onsamp(idx);
    offsamp = ud.T_events.offsamp(idx);
    mid = round((onsamp + offsamp) / 2);
    
    % --- 3. Calculate absolute anchor sample ---
    % Convert relative time (ms) to relative samples
    clicked_samp_rel = round(clicked_time_ms / 1000 * ud.sfx);
    % Add relative samples to midpoint sample
    manual_anchor_samp = mid + clicked_samp_rel;
    
    % --- 4. Store the result ---
    ud.Results.manual_anchor_samp(idx) = manual_anchor_samp;
    fprintf('Event %d: Anchor set to sample %d\n', idx, manual_anchor_samp);
    
    % --- 5. Save state and advance ---
    fig.UserData = ud;
    goToEvent(fig, idx + 1); % Auto-advance
end

function goToEvent(fig, newIndex)
    ud = fig.UserData;
    numEvents = height(ud.T_events);
    
    if newIndex < 1
        fprintf('Already at first event.\n');
        return;
    end
    
    if newIndex > numEvents
        fprintf('Reached last event. Click "Finish & Save".\n');
        ud.statusLabel.Text = sprintf('Last event! Click "Finish & Save"');
        return;
    end
    
    ud.CurrentIndex = newIndex;
    fig.UserData = ud;
    
    % Update the plot to show the new event
    updatePlot(fig);
end

function prevClicked(fig)
    ud = fig.UserData;
    goToEvent(fig, ud.CurrentIndex - 1);
end

function nextClicked(fig)
    ud = fig.UserData;
    goToEvent(fig, ud.CurrentIndex + 1);
end

function skipClicked(fig)
    ud = fig.UserData;
    idx = ud.CurrentIndex;
    
    % Record NaN for this event
    ud.Results.manual_anchor_samp(idx) = NaN;
    fprintf('Event %d: Skipped (NaN).\n', idx);
    
    % Save state and advance
    fig.UserData = ud;
    goToEvent(fig, idx + 1);
end

function saveClicked(fig)
    ud = fig.UserData;
    
    % Get save path
    [file, path] = uiputfile('*.csv', 'Save Manual Anchors', 'manual_anchors.csv');
    
    if isequal(file, 0) || isequal(path, 0)
        fprintf('Save cancelled.\n');
        return;
    end
    
    fullPath = fullfile(path, file);
    
    try
        writetable(ud.Results, fullPath);
        fprintf('SUCCESS: Manual anchors saved to %s\n', fullPath);
        
        % Ask to close
        selection = uiconfirm(fig, 'Results saved. Close the GUI?', 'Save Complete', ...
                               'Options',{'Close GUI', 'Keep Working'}, ...
                               'DefaultOption', 1, 'Icon', 'success');
        if strcmp(selection, 'Close GUI')
            delete(fig);
        end
        
    catch ME
        uialert(fig, sprintf('Failed to save CSV:\n%s', ME.message), 'Save Error', 'Icon', 'error');
    end
end

function closeGUI(fig)
    % Ask for confirmation before closing
    selection = uiconfirm(fig, 'Are you sure you want to close? Unsaved anchors will be lost.', 'Confirm Close', ...
                       'Options',{'Yes, Close', 'No, Cancel'}, ...
                       'DefaultOption', 2, 'Icon', 'warning');
                   
    if strcmp(selection, 'Yes, Close')
        % Clean up matfile object if it exists
        try
            ud = fig.UserData;
            clear ud.mf;
        catch
            % No UserData yet, or no mf. Fine to close.
        end
        delete(fig);
    end
end

% ======================================================================
%                  COPIED FROM YOUR OTHER SCRIPTS
% ======================================================================

function [onSamp, offSamp] = find_event_stamps(T, sfx)
% Robustly finds event sample columns, converting from seconds if needed.
    canon = lower(regexprep(T.Properties.VariableNames, '[^a-zA-Z0-9]', ''));
    i_onSamp  = find(strcmp(canon,'onsamp')  | strcmp(canon,'startsample') | strcmp(canon,'startsamp') | strcmp(canon,'on'), 1);
    i_offSamp = find(strcmp(canon,'offsamp') | strcmp(canon,'endsample')   | strcmp(canon,'endsamp')   | strcmp(canon,'off'), 1);
    i_onSec   = find(strcmp(canon,'onsec')   | strcmp(canon,'startsec')    | strcmp(canon,'onsecs'), 1);
    i_offSec  = find(strcmp(canon,'offsec')  | strcmp(canon,'endsec')      | strcmp(canon,'offsecs'), 1);
    
    if ~isempty(i_onSamp) && ~isempty(i_offSamp)
        fprintf('Reading event stamps from sample columns: %s, %s\n', ...
            T.Properties.VariableNames{i_onSamp}, T.Properties.VariableNames{i_offSamp});
        onSamp  = round(double(T{:, i_onSamp}));
        offSamp = round(double(T{:, i_offSamp}));
    elseif ~isempty(i_onSec) && ~isempty(i_offSec)
        fprintf('Reading event stamps from second columns: %s, %s (sfx=%.1f)\n', ...
            T.Properties.VariableNames{i_onSec}, T.Properties.VariableNames{i_offSec}, sfx);
        onSamp  = round(double(T{:, i_onSec})  * sfx);
        offSamp = round(double(T{:, i_offSec}) * sfx);
    else
        if width(T) >= 2
            fprintf('No standard columns found. Using first 2 columns as on/off samples.\n');
            onSamp  = round(double(T{:,1}));
            offSamp = round(double(T{:,2}));
        else
            error('Cannot find on/off stamp columns. Please name them "onsamp"/"offsamp" or "onsec"/"offsec".');
        end
    end
end

function chanLabels = get_channel_labels(chList, kept_channels)
% Creates string labels for channels, using CSC info if available.
    nCh = numel(chList);
    chanLabels = cell(nCh, 1);
    if isempty(kept_channels)
        for k = 1:nCh
            chanLabels{k} = sprintf('Row %d', chList(k));
        end
    else
        for k = 1:nCh
            ch = chList(k);
            if ch <= numel(kept_channels)
                chanLabels{k} = sprintf('Row %d (CSC%d)', ch, kept_channels(ch));
            else
                chanLabels{k} = sprintf('Row %d (CSC_OOB)', ch); % Out of bounds
            end
        end
    end
end