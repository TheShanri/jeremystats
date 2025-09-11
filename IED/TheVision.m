function TheVision(dataMatPath, spikesMatPath, varargin)
% PlotEventAllChannels_5to10
% Select events that appear on 5–10 channels (inclusive). For each such event:
%   - Extract a window around the event (default anchor = event midpoint).
%   - Plot ALL channels in a grid (works for 32, 64, or any number of channels).
%   - Channels where the event appeared (ech==true) are bold/dark; others thin/light.
%   - Save one PNG per event, include event index and active-channel count in filename.
%
% Inputs (same style as your other functions):
%   dataMatPath: MAT with fields d [nRows x nSamp], sfx (Hz), kept_channels (optional)
%   spikesMatPath: MAT with ets [N x 2], ech [N x nRows] (optional)
%
% Name-Value options:
%   'halfWidthMs'   (double) default 30e-3   % 30 ms half-window
%   'align'         ('midpoint'|'peak') default 'midpoint'
%   'peakPolarity'  ('abs'|'pos'|'neg') default 'abs'   % only used if align='peak'
%   'scaleToMV'     (double) default 1
%   'saveDir'       (string/char) default: alongside dataMatPath
%   'minCh'         (int) default 5
%   'maxCh'         (int) default 10
%   'gridCols'      (int) default 8           % good for 32/64 channels
%
% Example:
% PlotEventAllChannels_5to10('LL_input_data.mat','LLspikes.mat',...
%   'halfWidthMs',0.030,'align','midpoint','saveDir','C:\tmp\evtGrids')

% ---------- Parse ----------
p = inputParser;
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));
p.addRequired('spikesMatPath', @(s)ischar(s)||isstring(s));
p.addParameter('halfWidthMs', 30e-3, @(x)isfinite(x)&&x>0);
p.addParameter('align','midpoint', @(s)any(strcmpi(s,{'midpoint','peak'})));
p.addParameter('peakPolarity','abs', @(s) any(strcmpi(s,{'abs','pos','neg'})));
p.addParameter('scaleToMV', 1, @(x)isfinite(x)&&x>0);
p.addParameter('saveDir','', @(s)ischar(s)||isstring(s));
p.addParameter('minCh', 5, @(x)isfinite(x)&&x>=0);
p.addParameter('maxCh',10, @(x)isfinite(x)&&x>=0);
p.addParameter('gridCols',8, @(x)isfinite(x)&&x>=1);
p.parse(dataMatPath, spikesMatPath, varargin{:});

halfWidthMs  = p.Results.halfWidthMs;
alignMode    = lower(string(p.Results.align));
peakPolarity = lower(string(p.Results.peakPolarity));
scaleToMV    = p.Results.scaleToMV;
saveDir      = string(p.Results.saveDir);
minCh        = p.Results.minCh;
maxCh        = p.Results.maxCh;
gridCols     = p.Results.gridCols;

% ---------- Load ----------
if ~isfile(dataMatPath), error('Data MAT not found: %s', dataMatPath); end
if ~isfile(spikesMatPath), error('Spikes MAT not found: %s', spikesMatPath); end

mf = matfile(dataMatPath);
try, sfx = mf.sfx; catch, error('Missing "sfx" in data MAT.'); end
nRows = size(mf,'d',1);
nSamp = size(mf,'d',2);
try kept_channels = mf.kept_channels; catch, kept_channels = []; end

S = load(spikesMatPath,'ets','ech');
if ~isfield(S,'ets'), error('Spikes MAT must contain ets [N x 2].'); end
ets = S.ets;
Nevents = size(ets,1);

if isfield(S,'ech')
    ech = S.ech;
    if size(ech,2) ~= nRows
        if size(ech,2) < nRows, ech(:,end+1:nRows) = false; else, ech = ech(:,1:nRows); end
    end
else
    ech = true(Nevents, nRows); % if missing, treat as present on all channels
end

% ---------- Select events with channel count in [minCh, maxCh] ----------
chCounts = sum(ech,2);
sel = (chCounts >= minCh) & (chCounts <= maxCh);
evtIdx = find(sel);
if isempty(evtIdx)
    fprintf('No events with %d–%d channels.\n', minCh, maxCh);
    return;
end

% ---------- Setup ----------
HW = max(1, round(halfWidthMs * sfx));  % half-width in samples
tRelSamples = -HW:HW;
tRelMs = (tRelSamples / sfx) * 1e3;

if saveDir==""
    [outDir,~,~] = fileparts(dataMatPath);
else
    outDir = char(saveDir);
end
if ~exist(outDir,'dir'), mkdir(outDir); end

fprintf('Found %d event(s) with %d–%d channels. Window ±%d samples (%.2f ms).\n', ...
    numel(evtIdx), minCh, maxCh, HW, 1e3*HW/sfx);

% ---------- Iterate selected events ----------
for ii = 1:numel(evtIdx)
    e = evtIdx(ii);
    activeMask = ech(e,:);                 % 1 x nRows
    nActive    = sum(activeMask);
    s0_ev = max(1, ets(e,1));
    s1_ev = min(nSamp, ets(e,2));

    % Determine anchor (one anchor for all channels if midpoint; per-channel if peak)
    switch alignMode
        case "midpoint"
            anchor = round((s0_ev + s1_ev)/2);
            s0 = anchor - HW; s1 = anchor + HW;
            if s0 < 1 || s1 > nSamp
                fprintf('Evt %d skipped (window out of bounds).\n', e);
                continue;
            end
            % Pre-read all channels in a single call for speed
            Y = double(mf.d(:, s0:s1)) * scaleToMV;   % [nRows x winN]
            validRow = all(isfinite(Y),2);
            Y = Y(validRow, :);
            usedRows = find(validRow).';
        otherwise % 'peak'
            % Per-channel anchor within the event window
            usedRows = [];
            Y = [];
            for ch = 1:nRows
                yseg = double(mf.d(ch, s0_ev:s1_ev));
                if any(~isfinite(yseg)), continue; end
                switch peakPolarity
                    case 'pos', [~,k] = max(yseg);
                    case 'neg', [~,k] = min(yseg);
                    otherwise,  [~,k] = max(abs(yseg));
                end
                a = s0_ev + k - 1;
                s0 = a - HW; s1 = a + HW;
                if s0 < 1 || s1 > nSamp, continue; end
                y = double(mf.d(ch, s0:s1)) * scaleToMV;
                if any(~isfinite(y)), continue; end
                Y(end+1,:) = y; %#ok<AGROW>
                usedRows(end+1) = ch; %#ok<AGROW>
            end
    end

    if isempty(Y)
        fprintf('Evt %d: no valid channel windows, skipping.\n', e);
        continue;
    end

    % ---------- Figure: grid of subplots ----------
    nUsed = numel(usedRows);
    nCols = min(gridCols, nUsed);
    nRowsGrid = ceil(nUsed / nCols);

    f = figure('Color','w','Position',[60 60 1300 900],'Visible','off');
    tl = tiledlayout(f, nRowsGrid, nCols, 'Padding','compact', 'TileSpacing','compact');

    for k = 1:nUsed
        ch = usedRows(k);
        nexttile(tl);
        hold on; box on; grid on;

        % Styling: bold/dark if active; thin/light otherwise
        isActive = activeMask(ch);
        if isActive
            lw = 1.4; col = [0 0 0];         % active: bold, dark
        else
            lw = 0.7; col = [0.5 0.5 0.5];   % inactive: thin, gray
        end

        plot(tRelMs, Y(k,:), 'LineWidth', lw, 'Color', col);
        xline(0,'--k','LineWidth',0.8); yline(0,':','Color',[0.7 0.7 0.7]);

        if ~isempty(kept_channels)
            ttl = sprintf('row %d (CSC%d)%s', ch, kept_channels(ch), tern(isActive,' *',''));
        else
            ttl = sprintf('row %d%s', ch, tern(isActive,' *',''));
        end
        title(ttl, 'FontSize',8);
        % Compact axes
        ax = gca;
        ax.FontSize = 8;
        if k <= (nUsed - nCols) % hide xlabels except bottom row
            ax.XTickLabel = [];
        else
            xlabel('ms');
        end
        if mod(k-1,nCols)~=0  % hide ylabels except first column
            ax.YTickLabel = [];
        else
            ylabel('mV');
        end
    end

    % ---------- Super title + save ----------
    titleStr = sprintf('Event %03d  |  Active channels: %d  |  Align: %s  |  Win: \\pm%.1f ms', ...
                       e, nActive, alignMode, 1e3*HW/sfx);
    sgtitle(tl, titleStr, 'FontSize',12, 'FontWeight','bold');

    outPng = fullfile(outDir, sprintf('Evt%03d_%dch_align-%s_HW%ds_%dms.png', ...
                    e, nActive, alignMode, HW, round(1e3*HW/sfx)));
    exportgraphics(f, outPng, 'Resolution', 220);
    close(f);
    fprintf('Saved: %s\n', outPng);
end

fprintf('Done. Output dir: %s\n', outDir);

% ---------- helpers ----------
function s = tern(cond, a, b), if cond, s=a; else, s=b; end
end
