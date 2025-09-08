function SpikePerEventCrossChannelAvg(dataMatPath, spikesMatPath, varargin)
% SpikePerEventCrossChannelAvg
% For EACH detected event, compute cross-channel averages (not across events):
%   - ref-only        (reference channel waveform)
%   - ±8 channels     (avg across rows [ref-8 .. ref+8], clipped to valid)
%   - ±16 channels
%   - all channels    (avg across all rows of d)
%
% Alignment options per event:
%   - 'midpoint' : center = (on+off)/2
%   - 'peak'     : center at per-event, per-reference-channel peak
%                  (peakPolarity='abs' | 'pos' | 'neg')
%
% Reference channel selection per event:
%   - 'maxabs' (default): among involved rows, pick the one with largest |peak| within the event
%   - 'first'           : pick the first involved row
%
% Saves a PNG per event with the 4 overlays.
%
% Usage:
%   SpikePerEventCrossChannelAvg( ...
%       'C:\...\LL_input_..._mex_disk.mat', ...
%       'C:\...\LL_input_..._LLspikes_YYYYMMDD_HHMMSS.mat', ...
%       'preSec',0.25,'postSec',0.25, ...
%       'align','peak','peakPolarity','abs', ...
%       'refChoice','maxabs', ...
%       'eventIndices',[], 'maxEvents',Inf, ...
%       'saveDir','' );
%
% Notes:
% - Reads from disk via matfile; does NOT load the full matrix into RAM
% - Neighbor groups are by **row index** in d (mapped to original channel labels via 'kept_channels')

%% ---- Parse inputs ----
p = inputParser;
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));
p.addRequired('spikesMatPath', @(s)ischar(s)||isstring(s));
p.addParameter('preSec', 0.25, @(x)isfinite(x)&&x>0);
p.addParameter('postSec', 0.25, @(x)isfinite(x)&&x>0);
p.addParameter('align','peak', @(s) any(strcmpi(s,{'peak','midpoint'})));
p.addParameter('peakPolarity','abs', @(s) any(strcmpi(s,{'abs','pos','neg'})));
p.addParameter('refChoice','maxabs', @(s) any(strcmpi(s,{'maxabs','first'})));
p.addParameter('eventIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('maxEvents', Inf, @(x) isfinite(x) || isinf(x));
p.addParameter('saveDir','', @(s)ischar(s)||isstring(s));
p.parse(dataMatPath, spikesMatPath, varargin{:});

preSec       = p.Results.preSec;
postSec      = p.Results.postSec;
alignMode    = lower(string(p.Results.align));
peakPolarity = lower(string(p.Results.peakPolarity));
refChoice    = lower(string(p.Results.refChoice));
eventIndices = p.Results.eventIndices;
maxEvents    = p.Results.maxEvents;
saveDir      = string(p.Results.saveDir);

if ~isfile(dataMatPath), error('Data MAT not found: %s', dataMatPath); end
if ~isfile(spikesMatPath), error('Spikes MAT not found: %s', spikesMatPath); end

%% ---- Open data & spikes ----
mf = matfile(dataMatPath);
try
    sfx           = mf.sfx;
    kept_channels = mf.kept_channels;      % original CSC numbers for each row of d
catch
    error('Missing sfx/kept_channels in data file. Use the provided converter.');
end
nRows  = size(mf,'d',1);
nSamp  = size(mf,'d',2);

S = load(spikesMatPath,'ets','ech');
if ~isfield(S,'ets') || ~isfield(S,'ech')
    error('Spikes file must contain ets and ech.');
end
ets = S.ets;             % [N x 2] event on/off (samples)
ech = S.ech;             % [N x nRows] logical: rows involved per event
Nevents = size(ets,1);
if size(ech,2) ~= nRows
    % pad or trim for robustness
    if size(ech,2) < nRows, ech(:,end+1:nRows) = false; else, ech = ech(:,1:nRows); end
end

% Choose output directory
if saveDir == ""
    [outDir, baseName, ~] = fileparts(dataMatPath);
else
    outDir = char(saveDir);
end
if ~exist(outDir,'dir'), mkdir(outDir); end

% Time axis window
preN  = max(1, round(preSec  * sfx));
postN = max(1, round(postSec * sfx));
winN  = preN + postN + 1;
tRel  = (-preN:postN) / sfx;

% Which events to process
if isempty(eventIndices)
    evList = (1:Nevents).';
else
    evList = eventIndices(:);
    evList = evList(evList>=1 & evList<=Nevents);
end
if isfinite(maxEvents)
    evList = evList(1:min(numel(evList), maxEvents));
end
fprintf('Processing %d event(s) out of %d total.\n', numel(evList), Nevents);

%% ---- Main loop over events ----
for ii = 1:numel(evList)
    ei = evList(ii);
    rowsInvolved = find(ech(ei,:));
    if isempty(rowsInvolved)
        continue; % no channels involved? skip
    end

    % ----- pick reference row for this event -----
    switch refChoice
        case "first"
            refRow = rowsInvolved(1);
        otherwise % "maxabs"
            % pick involved row whose window peak |amp| inside the event is maximal
            [~, refRow] = pickMaxAbsRow(mf, rowsInvolved, ets(ei,:), peakPolarity);
    end
    refCSC = kept_channels(refRow);

    % ----- anchor selection -----
    switch alignMode
        case "midpoint"
            anchor = round( (ets(ei,1) + ets(ei,2))/2 );
        otherwise % 'peak' on reference row within event
            s0_ev = max(1,  ets(ei,1));
            s1_ev = min(nSamp, ets(ei,2));
            anchor = findPeakAnchor(mf, refRow, s0_ev, s1_ev, peakPolarity);
    end

    % window around anchor
    s0 = anchor - preN;  s1 = anchor + postN;
    if s0 < 1 || s1 > nSamp
        % If near edges: skip
        fprintf('Event %d skipped (window out of bounds)\n', ei);
        continue;
    end

    % ----- build groups -----
    grp1 = refRow;
    grp2 = clampIdx((refRow-8):(refRow+8), nRows);
    grp3 = clampIdx((refRow-16):(refRow+16), nRows);
    grp4 = 1:nRows;

    % ----- read and average each group -----
    A_ref  = meanRowsWindow(mf, grp1, s0, s1);    % 1 x winN
    A_pm8  = meanRowsWindow(mf, grp2, s0, s1);
    A_pm16 = meanRowsWindow(mf, grp3, s0, s1);
    A_all  = meanRowsWindow(mf, grp4, s0, s1);

    % ----- plot & save -----
    f = figure('Color','w','Position',[80 80 1100 520], 'Visible','off');
    ax = axes('Parent',f); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    colors = lines(4);
    plot(ax, tRel, A_ref,  'LineWidth',1.8,'Color',colors(1,:));
    plot(ax, tRel, A_pm8,  'LineWidth',1.8,'Color',colors(2,:));
    plot(ax, tRel, A_pm16, 'LineWidth',1.8,'Color',colors(3,:));
    plot(ax, tRel, A_all,  'LineWidth',1.8,'Color',colors(4,:));
    xline(ax, 0, '--k','LineWidth',1.2); yline(ax,0,':','Color',[0.6 0.6 0.6]);

    xlabel(ax, 'Time relative to anchor (s)');
    ylabel(ax, 'Amplitude (AD counts)');
    ttl = sprintf('Event %d  |  ref: row %d (CSC%d)  |  align=%s', ei, refRow, refCSC, alignMode);
    title(ax, ttl);
    legend(ax, {'ref-only','\pm8','\pm16','all'}, 'Location','best');
    xlim(ax, [tRel(1) tRel(end)]);

    % name & save
    tOn  = ets(ei,1)/sfx;  tOff = ets(ei,2)/sfx;  tMid = 0.5*(tOn+tOff);
    outPng = fullfile(outDir, sprintf('EventAvg_e%04d_refCSC%d_align-%s_pre%.3f_post%.3f_anchor%.3fs.png', ...
                        ei, refCSC, alignMode, preSec, postSec, round(anchor/sfx,3)));
    exportgraphics(ax, outPng, 'Resolution', 200);
    close(f);

    % progress
    if mod(ii,25)==0 || ii==numel(evList)
        fprintf('Saved %d/%d (last: %s)\n', ii, numel(evList), outPng);
    end
end

fprintf('Done. Images saved to: %s\n', outDir);

%% ====================== helpers ======================
function idx = clampIdx(idx, nMax)
    idx = idx(idx>=1 & idx<=nMax);
end

function [maxAbsVal, bestRow] = pickMaxAbsRow(mf, rows, evWin, polarity)
    % pick row with largest (abs/pos/neg) peak within event window
    s0 = max(1, evWin(1)); s1 = min(size(mf,'d',2), evWin(2));
    maxAbsVal = -Inf; bestRow = rows(1);
    for r = rows(:)'
        y = double(mf.d(r, s0:s1));
        switch lower(polarity)
            case 'pos'
                v = max(y);
            case 'neg'
                v = -min(y); % larger is more negative in magnitude
            otherwise % 'abs'
                v = max(abs(y));
        end
        if v > maxAbsVal
            maxAbsVal = v; bestRow = r;
        end
    end
end

function anchor = findPeakAnchor(mf, row, s0, s1, polarity)
    y = double(mf.d(row, s0:s1));
    switch lower(polarity)
        case 'pos'
            [~,k] = max(y);
        case 'neg'
            [~,k] = min(y);
        otherwise % 'abs'
            [~,k] = max(abs(y));
    end
    anchor = s0 + k - 1;
end

function wavg = meanRowsWindow(mf, rows, s0, s1)
    % average across specified rows for window [s0:s1], ignoring NaNs
    if numel(rows)==1
        Y = double(mf.d(rows, s0:s1));
        wavg = Y(:).';  % 1 x winN
        return;
    end
    % try reading as a slab (row subset by window)
    Y = double(mf.d(rows, s0:s1));     % size: nRowsSel x winN
    M = isfinite(Y);
    if any(~M,'all')
        numer = sum(Y .* M, 1);
        denom = sum(M, 1);
        denom(denom==0) = 1; % avoid zero-div
        wavg = numer ./ denom;
    else
        wavg = mean(Y, 1);
    end
end

end
