function TheVisionOverlay(dataMatPath, spikesMatPath, varargin)
% OverlayEventAcrossChannels
% For each event that appears on 5–8 channels (inclusive), produce a SINGLE
% overlay plot (one axes) of channel waveforms centered on a *global*
% event anchor = median of per-channel peak times among channels where ech==true.
%
% - Overlay includes exactly N traces by down/selecting rows:
%       'channelStride' = 1  -> all rows (e.g., 64)
%       'channelStride' = 2  -> every 2nd row (e.g., 32: 2,4,6,... if offset=0)
%       'channelStride' = 4  -> every 4th row (e.g., 16), etc.
%   Use 'channelOffset' to choose where the stride starts (0-based).
%   Example: stride=2, offset=1 -> rows 1,3,5,... (i.e., “odd” if rows are 1-indexed).
%
% - Styling:
%     * Active (ech==true) channels: bold, black
%     * Inactive: thin, gray
%     * Fixed symmetric y-limits per figure (computed from all plotted traces)
%
% Inputs:
%   dataMatPath: MAT with fields d [nRows x nSamp], sfx (Hz), kept_channels (optional)
%   spikesMatPath: MAT with ets [N x 2], ech [N x nRows] (optional)
%
% Name-Value options:
%   'halfWidthMs'     (double) default 30e-3
%   'peakPolarity'    ('abs'|'pos'|'neg') default 'abs' (for peak-picking on ech==true set)
%   'scaleToMicroV'   (double) default 1   (multiply raw units -> µV)
%   'saveDir'         (string/char) default alongside dataMatPath
%   'minCh'           (int) default 5
%   'maxCh'           (int) default 8
%   'channelStride'   (int) default 1      (1=all, 2=every 2nd, 4=every 4th, ...)
%   'channelOffset'   (int) default 0      (0..stride-1; which row index to start at)
%
% Output:
%   Saves one PNG per qualifying event:  Overlay_EvtNNN_<nPlotted>rows_HW<samples>_<ms>.png

% ---------- Parse ----------
p = inputParser;
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));
p.addRequired('spikesMatPath', @(s)ischar(s)||isstring(s));
p.addParameter('halfWidthMs', 30e-3, @(x)isfinite(x)&&x>0);
p.addParameter('peakPolarity','abs', @(s) any(strcmpi(s,{'abs','pos','neg'})));
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x)&&x>0);
p.addParameter('saveDir','', @(s)ischar(s)||isstring(s));
p.addParameter('minCh', 5, @(x)isfinite(x)&&x>=0);
p.addParameter('maxCh', 8, @(x)isfinite(x)&&x>=0);
p.addParameter('channelStride', 1, @(x)isfinite(x)&&x>=1&&mod(x,1)==0);
p.addParameter('channelOffset', 0, @(x)isfinite(x)&&x>=0&&mod(x,1)==0);
p.parse(dataMatPath, spikesMatPath, varargin{:});

halfWidthMs    = p.Results.halfWidthMs;
peakPolarity   = lower(string(p.Results.peakPolarity));
scaleToMicroV  = p.Results.scaleToMicroV;
saveDir        = string(p.Results.saveDir);
minCh          = p.Results.minCh;
maxCh          = p.Results.maxCh;
channelStride  = p.Results.channelStride;
channelOffset  = p.Results.channelOffset;

% ---------- Load ----------
if ~isfile(dataMatPath), error('Data MAT not found: %s', dataMatPath); end
if ~isfile(spikesMatPath), error('Spikes MAT not found: %s', spikesMatPath); end

mf = matfile(dataMatPath);
try, sfx = mf.sfx; catch, error('Missing "sfx" in data MAT.'); end
nRows = size(mf,'d',1);
nSamp = size(mf,'d',2);
try kept_channels = mf.kept_channels; catch, kept_channels = []; end %#ok<NASGU>

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
tRelSamples = -HW:HW; %#ok<NASGU>
tRelMs = (tRelSamples / sfx) * 1e3;

if saveDir==""
    [outDir,~,~] = fileparts(dataMatPath);
else
    outDir = char(saveDir);
end
if ~exist(outDir,'dir'), mkdir(outDir); end

fprintf('Overlay: %d qualifying event(s) (%d–%d ch). Window ±%d samples (%.2f ms). Using stride=%d offset=%d. Scale=%g µV.\n', ...
    numel(evtIdx), minCh, maxCh, HW, 1e3*HW/sfx, channelStride, channelOffset, scaleToMicroV);

% ---------- Build row selection by stride/offset ----------
% MATLAB rows are 1-based. We implement: keep rows r where mod(r-1, stride) == offset
offset = mod(channelOffset, channelStride);
rowKeepMask = arrayfun(@(r) mod(r-1, channelStride) == offset, 1:nRows);
rowKeepIdx  = find(rowKeepMask);     % these are the rows we will overlay

% ---------- Iterate selected events ----------
for ii = 1:numel(evtIdx)
    e = evtIdx(ii);
    maskActive = ech(e,:);                 % logical 1 x nRows
    s0_ev = max(1, ets(e,1));
    s1_ev = min(nSamp, ets(e,2));

    % --- 1) Find global anchor from *active* channels only (ech==true) ---
    activeRows = find(maskActive);
    if isempty(activeRows)
        fprintf('Evt %d: no active rows flagged; skipping.\n', e);
        continue;
    end

    % Per-active-channel peak indices (within [s0_ev:s1_ev]) in raw units (not scaled)
    peakIdx = nan(numel(activeRows),1);
    for k = 1:numel(activeRows)
        ch = activeRows(k);
        yseg = double(mf.d(ch, s0_ev:s1_ev));
        if any(~isfinite(yseg)), continue; end
        switch peakPolarity
            case "pos", [~,kpk] = max(yseg);
            case "neg", [~,kpk] = min(yseg);
            otherwise,  [~,kpk] = max(abs(yseg)); % 'abs'
        end
        peakIdx(k) = s0_ev + kpk - 1;
    end
    peakIdx = peakIdx(isfinite(peakIdx));
    if isempty(peakIdx)
        fprintf('Evt %d: could not compute peaks on active channels; skipping.\n', e);
        continue;
    end
    % Global anchor = median of per-channel peaks (robust)
    anchor = round(median(peakIdx));
    s0 = anchor - HW; s1 = anchor + HW;
    if s0 < 1 || s1 > nSamp
        fprintf('Evt %d: window out of bounds @ anchor %d; skipping.\n', e, anchor);
        continue;
    end

    % --- 2) Extract windows for *selected* rows (by stride) centered on this anchor ---
    rowsToPlot = rowKeepIdx;
    % If you want exactly, say, 64 traces even if nRows < 64, we just take what's available.
    nPlot = numel(rowsToPlot);
    Y = nan(nPlot, 2*HW+1);
    for k = 1:nPlot
        ch = rowsToPlot(k);
        y = double(mf.d(ch, s0:s1)) * scaleToMicroV; % convert to µV
        if any(~isfinite(y)), continue; end
        Y(k,:) = y;
    end

    % If everything is NaN, skip
    if all(~isfinite(Y(:)))
        fprintf('Evt %d: no valid windows for selected rows; skipping.\n', e);
        continue;
    end

    % --- 3) Fixed symmetric y-limits for this overlay ---
    maxAbs = max(abs(Y(:)), [], 'omitnan');
    if ~isfinite(maxAbs) || maxAbs<=0, maxAbs = 1; end
    pad  = 0.05;
    span = (1+pad) * maxAbs;
    yL   = [-span, span];

    % --- 4) Plot overlay ---
    f = figure('Color','w','Position',[80 80 1000 700],'Visible','off');
    ax = axes('Parent',f); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    for k = 1:nPlot
        ch = rowsToPlot(k);
        y  = Y(k,:);
        if all(~isfinite(y)), continue; end
        isActive = maskActive(ch);
        if isActive
            lw = 1.6; col = [0 0 0];       % active: bold, black
        else
            lw = 0.8; col = [0.6 0.6 0.6]; % inactive: thin, gray
        end
        plot(ax, tRelMs, y, 'LineWidth', lw, 'Color', col);
    end

    xline(ax,0,'--k','LineWidth',0.9);
    yline(ax,0,':','Color',[0.7 0.7 0.7]);

    ylim(ax, yL);
    xlabel(ax, 'ms');
    ylabel(ax, '\muV');

    nActive = sum(maskActive);
    ttl = sprintf('Event %03d  |  Active channels: %d  |  Anchor: median peak @ [%d]  |  Win: \\pm%.1f ms  |  Plotted rows: %d (stride=%d, offset=%d)', ...
                   e, nActive, anchor, 1e3*HW/sfx, nPlot, channelStride, offset);
    title(ax, ttl, 'FontSize', 12, 'FontWeight', 'bold');

    % Optional: tiny legend-like note
    txt = sprintf('\\fontsize{8}Active=bold black (%d)   Inactive=thin gray (%d)   Units=\\muV   yLim=\\pm%.1f', ...
                  nActive, nPlot - nActive, span);
    text(ax, 0.01, 0.98, txt, 'Units','normalized', 'VerticalAlignment','top', ...
         'BackgroundColor','w', 'Margin',3, 'EdgeColor',[0.85 0.85 0.85], 'Interpreter','tex');

    % --- 5) Save ---
    msWin = round(1e3*HW/sfx);
    outPng = fullfile(outDir, sprintf('Overlay_Evt%03d_%drows_stride%d_off%d_HW%ds_%dms_uV.png', ...
                                      e, nPlot, channelStride, offset, HW, msWin));
    exportgraphics(f, outPng, 'Resolution', 220);
    close(f);
    fprintf('Saved overlay: %s\n', outPng);
end

fprintf('Done. Output dir: %s\n', outDir);
end
