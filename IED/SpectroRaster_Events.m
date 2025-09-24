function SpectralRaster_Events(inputFolder, dataMatPath, varargin)
% SpectralRaster_Events
% For each event, create a stacked spectrogram figure: one axes per channel.
% X-axis = time (ms), Y-axis = frequency (Hz), color = power (linear or dB).
%
% OUTPUT FOLDERS (created if missing)
%   <inputFolder>/Spectral Raster Output/Solid
%   <inputFolder>/Spectral Raster Output/Sputter
%
% Event IDs are inferred from existing PNG names in:
%   <inputFolder>/Solid and <inputFolder>/Sputter
% (Pattern 'Evt(\d+)' same as VoltageRaster_Events.)
%
% Default anchor: first channel's POSITIVE PEAK within ±5 ms around midpoint.
% Default time window for the spectrogram stack: ±10 ms.
% Global color limits are computed across ALL events (both groups) for comparability.
%
% REQUIRED data MAT fields:
%   d [nRows x nSamp], sfx (Hz), kept_channels (optional)
%
% ---------------- Args ----------------
p = inputParser;
p.addRequired('inputFolder', @(s)ischar(s)||isstring(s));
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));

% same inputs as your voltage raster
p.addParameter('excelPath',"", @(s)ischar(s)||isstring(s));
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('scaleToMicroV', 1, @(x)isnumeric(x) && all(isfinite(x)) && all(x>0));

p.addParameter('anchorMode','firstChMax', @(s) any(strcmpi(s,{'firstChMax','midpoint'})));
p.addParameter('anchorHalfWidthMs', 5e-3,  @(x)isfinite(x)&&x>0);

% keep the time scale at ±10 ms (as requested)
p.addParameter('winHalfWidthMs', 10e-3, @(x)isfinite(x)&&x>0);

% spectrogram params (sensible defaults for short windows)
p.addParameter('fRangeHz', [1 150], @(v)isnumeric(v) && numel(v)==2 && v(1)>=0 && v(2)>v(1));
p.addParameter('winMs', 4e-3, @(x)isfinite(x)&&x>0);           % analysis window length
p.addParameter('overlapFrac', 0.75, @(x)isfinite(x)&&x>=0&&x<1);
p.addParameter('nfft', [], @(x) isempty(x) || (isscalar(x) && x>0));  % optional override
p.addParameter('powerScale','db', @(s) any(strcmpi(s,{'db','linear'}))); % color scale

% global CLim controls for power
% If climPower is [] -> auto robust across ALL events (upper = yRobustPct).
% For 'db', CLim = [lowerPct, upperPct] in dB; for 'linear', in linear power units.
p.addParameter('climPower', [], @(v) isempty(v) || (isnumeric(v) && (numel(v)==2)));
p.addParameter('yRobustPct', 99.5, @(x)isfinite(x) && x>0 && x<100);
p.addParameter('lowPct', 1.0, @(x)isfinite(x) && x>=0 && x<100);    % lower percentile floor
p.addParameter('climPadFrac', 0.10, @(x)isfinite(x) && x>=0 && x<=0.5);

p.addParameter('maxEventsPerGroup', [], @(x) isempty(x) || (isscalar(x) && x>0));

p.parse(inputFolder, dataMatPath, varargin{:});

inputFolder   = string(p.Results.inputFolder);
dataMatPath   = string(p.Results.dataMatPath);
excelPath     = string(p.Results.excelPath);
channelIdx    = p.Results.channelIndices;
scaleToMicroV = p.Results.scaleToMicroV;

anchorMode    = lower(string(p.Results.anchorMode));
anchorHWms    = p.Results.anchorHalfWidthMs;

winHalfMs     = p.Results.winHalfWidthMs;

fRangeHz      = p.Results.fRangeHz;
winMs         = p.Results.winMs;
overlapFrac   = p.Results.overlapFrac;
nfftOpt       = p.Results.nfft;
powerScale    = lower(string(p.Results.powerScale));

climPowerOpt  = p.Results.climPower;
yRobustPct    = p.Results.yRobustPct;
lowPct        = p.Results.lowPct;
climPadFrac   = p.Results.climPadFrac;

maxEventsPer  = p.Results.maxEventsPerGroup;

% ---------------- Layout & IO ----------------
solidDir   = fullfile(inputFolder, "Solid");
sputterDir = fullfile(inputFolder, "Sputter");
assert(isfolder(solidDir),   'Missing folder: %s', solidDir);
assert(isfolder(sputterDir), 'Missing folder: %s', sputterDir);

if excelPath == ""
    xl = dir(fullfile(inputFolder, "*.xlsx"));
    assert(~isempty(xl), 'No Excel file (*.xlsx) found in %s', inputFolder);
    excelPath = fullfile(xl(1).folder, xl(1).name);
end
assert(isfile(excelPath), 'Excel not found: %s', excelPath);

outRoot = fullfile(inputFolder, "Spectral Raster Output");
outSOL  = fullfile(outRoot, "Solid");
outSPU  = fullfile(outRoot, "Sputter");
if ~exist(outSOL,'dir'), mkdir(outSOL); end
if ~exist(outSPU,'dir'), mkdir(outSPU); end

% ---------------- Data ----------------
assert(isfile(dataMatPath), 'Data MAT not found: %s', dataMatPath);
mf = matfile(dataMatPath);
try sfx = mf.sfx; catch, error('Missing "sfx" in data MAT.'); end
nRowsAll = size(mf,'d',1);
nSamp    = size(mf,'d',2);
try kept_channels = mf.kept_channels; catch, kept_channels = []; end %#ok<NASGU>

if isempty(channelIdx)
    chList = 1:nRowsAll;
else
    chList = channelIdx(:).';
    chList = chList(chList>=1 & chList<=nRowsAll);
end
nCh = numel(chList);

% allow per-row scaling
if numel(scaleToMicroV) == 1
    scaleVec = repmat(scaleToMicroV, nRowsAll, 1);
else
    assert(numel(scaleToMicroV) >= nRowsAll, 'scaleToMicroV must be scalar or >= nRowsAll length.');
    scaleVec = scaleToMicroV(:);
end

% ---------------- Windows ----------------
HWwin    = max(1, round(winHalfMs   * sfx)); % ± window (±10 ms default)
HWanchor = max(1, round(anchorHWms  * sfx)); % ± anchor search (±5 ms)
tRelMs   = (-HWwin:HWwin) / sfx * 1e3;       % time axis for plotting labels
segN     = numel(tRelMs);

fprintf(['SpectralRaster_Events: sfx=%.1f Hz | spectrogram stack window ±%.1f ms | ' ...
         'anchor=%s (±%.1f ms) | fRange=[%g %g] Hz | win=%.1f ms overlap=%.0f%% | scale=%s\n'], ...
         sfx, 1e3*HWwin/sfx, anchorMode, 1e3*HWanchor/sfx, fRangeHz(1), fRangeHz(2), ...
         1e3*winMs, 100*overlapFrac, powerScale);

% ---------------- Read Excel -> samples per row ----------------
T = readtable(excelPath, 'ReadVariableNames', true);
canon = lower(regexprep(T.Properties.VariableNames, '[^a-zA-Z0-9]', ''));
i_onSamp  = find(strcmp(canon,'onsamp')  | strcmp(canon,'startsample') | strcmp(canon,'startsamp') | strcmp(canon,'on'), 1);
i_offSamp = find(strcmp(canon,'offsamp') | strcmp(canon,'endsample')   | strcmp(canon,'endsamp')   | strcmp(canon,'off'), 1);
i_onSec   = find(strcmp(canon,'onsec')   | strcmp(canon,'startsec')    | strcmp(canon,'onsecs'), 1);
i_offSec  = find(strcmp(canon,'offsec')  | strcmp(canon,'endsec')      | strcmp(canon,'offsecs'), 1);

if ~isempty(i_onSamp) && ~isempty(i_offSamp)
    onSamp  = double(T{:, i_onSamp});
    offSamp = double(T{:, i_offSamp});
elseif ~isempty(i_onSec) && ~isempty(i_offSec)
    onSamp  = round(double(T{:, i_onSec})  * sfx);
    offSamp = round(double(T{:, i_offSec}) * sfx);
else
    assert(width(T) >= 2, 'Excel must have [on_samp, off_samp] or [on_sec, off_sec].');
    onSamp  = double(T{:,1});
    offSamp = double(T{:,2});
end

onSamp  = max(1, min(onSamp,  nSamp));
offSamp = max(1, min(offSamp, nSamp));
NrowsXL = numel(onSamp);

% ---------------- Event IDs from PNG names ----------------
evtSOL = parseEvtNumsFromPngs(solidDir);
evtSPU = parseEvtNumsFromPngs(sputterDir);
fprintf('Found %d SOLID, %d SPUTTER events (by filenames).\n', numel(evtSOL), numel(evtSPU));

if ~isempty(maxEventsPer)
    evtSOL = evtSOL(1:min(end, maxEventsPer));
    evtSPU = evtSPU(1:min(end, maxEventsPer));
end

% ---------------- Global CLim across ALL events (Solid + Sputter) ----------------
if isempty(climPowerOpt)
    fprintf('Scanning events to compute global power CLim (lowPct=%.1f%%, hiPct=%.2f%%, scale=%s)...\n', ...
        lowPct, yRobustPct, powerScale);
    [pLow, pHigh] = scanGlobalPowerLimits([evtSOL(:); evtSPU(:)]);
    % pad headroom on the upper limit
    if strcmp(powerScale,'db')
        climGlobal = [pLow, pHigh + climPadFrac*(pHigh - pLow)];
    else
        climGlobal = [pLow, pHigh*(1+climPadFrac)];
    end
else
    climGlobal = climPowerOpt(:).';
end
fprintf('Global CLim (power, %s) = [%.3f, %.3f]\n', powerScale, climGlobal(1), climGlobal(2));

% ---------------- Render groups ----------------
renderGroup(evtSOL, outSOL, 'SOLID', climGlobal);
renderGroup(evtSPU, outSPU, 'SPUTTER', climGlobal);

fprintf('Done. Output in: %s\n', outRoot);

% ======================================================================
%                                HELPERS
% ======================================================================

function [pLow, pHigh] = scanGlobalPowerLimits(evtList)
    % Walk events; build robust lower/upper percentiles of all power pixels
    acc = []; %#ok<NASGU>
    pLow = NaN; pHigh = NaN;

    % We won't store pixels (too big), we aggregate percentiles per-event and combine.
    lows  = nan(numel(evtList),1);
    highs = nan(numel(evtList),1);

    for ii = 1:numel(evtList)
        e = evtList(ii);
        rowXL = e;
        if rowXL < 1 || rowXL > NrowsXL, continue; end

        [ok, s0, s1] = getAnchoredWindow(rowXL);
        if ~ok, continue; end

        % For percentile scan, sample a subset of channels to keep it light if many channels
        chSub = chList;
        if numel(chSub) > 32
            chSub = chSub(round(linspace(1, numel(chSub), 32)));
        end

        powPixels = [];
        for ch = chSub
            sc = scaleVec(ch);
            x  = double(mf.d(ch, s0:s1)) * sc;
            [P, ~, ~] = computeSpec(x); % per-channel
            if strcmp(powerScale,'db')
                pow = 10*log10(P + eps);
            else
                pow = P;
            end
            powPixels = [powPixels; pow(:)]; %#ok<AGROW>
        end
        if ~isempty(powPixels)
            lows(ii)  = prctile(powPixels, lowPct);
            highs(ii) = prctile(powPixels, yRobustPct);
        end
    end

    % combine per-event bounds conservatively
    if any(isfinite(lows)),  pLow  = min(lows, [], 'omitnan'); else, pLow = 0; end
    if any(isfinite(highs)), pHigh = max(highs,[], 'omitnan'); else, pHigh = 1; end

    if ~isfinite(pLow),  pLow  = 0; end
    if ~isfinite(pHigh), pHigh = pLow + 1; end
end

function renderGroup(evtList, outDir, tag, clim)
    if isempty(evtList)
        warning('%s: no events to render.', tag);
        return;
    end
    for ii = 1:numel(evtList)
        e = evtList(ii);
        rowXL = e;
        if rowXL < 1 || rowXL > NrowsXL
            fprintf('%s evt %d: out of Excel bounds. Skipping.\n', tag, e);
            continue;
        end

        [ok, s0, s1] = getAnchoredWindow(rowXL);
        if ~ok
            fprintf('%s evt %d: bad/missing anchor/window. Skipping.\n', tag, e);
            continue;
        end

        % ---- Build spectrogram stack: one per channel ----
        % We also reuse the same time vector across channels
        perRowPx = 85; basePx = 240; maxPx = 5200;
        figH = min(maxPx, basePx + perRowPx * nCh);
        f = figure('Color','w','Position',[80 80 1050 figH],'Visible','off');
        tl = tiledlayout(f, nCh, 1, 'Padding','compact', 'TileSpacing','compact');

        t0_rel_s = -HWwin / sfx;  % start of our segment relative to anchor (s), so 0 is center

        Tplot = []; Fplot = [];
        for k = 1:nCh
            ch = chList(k);
            sc = scaleVec(ch);
            x  = double(mf.d(ch, s0:s1)) * sc;

            [P, F, T] = computeSpec(x);
            % Convert T to ms relative to anchor (segment start is -HWwin)
            Tms = (T + t0_rel_s) * 1e3;

            if isempty(Tplot), Tplot = Tms; Fplot = F; end  % reuse for axis labels

            if strcmp(powerScale,'db')
                Z = 10*log10(P + eps);
            else
                Z = P;
            end

            ax = nexttile(tl); %#ok<LUNTAG>
            imagesc(ax, Tms, F, Z);
            axis(ax, 'xy'); colormap(ax, jet); caxis(ax, clim);
            xline(ax, 0, '--k', 'LineWidth', 0.7);
            if k < nCh
                set(ax,'XTickLabel',[]);
            else
                xlabel(ax, 'Time (ms)');
            end
            if ~isempty(kept_channels)
                ttl = sprintf('row %d (CSC%d)', ch, kept_channels(ch));
            else
                ttl = sprintf('row %d', ch);
            end
            title(ax, ttl, 'FontSize', 9, 'FontWeight','normal');
            ylabel(ax, 'Hz');
            set(ax,'FontSize',8);
        end

        % Group-level title
        sg = sprintf('%s  |  Evt %d  |  anchor=%s (\\pm%.1f ms)  |  window=\\pm%.1f ms  |  ch=%d  |  f=[%g %g] Hz  |  scale=%s', ...
            tag, e, char(anchorMode), 1e3*HWanchor/sfx, 1e3*HWwin/sfx, nCh, fRangeHz(1), fRangeHz(2), powerScale);
        sgtitle(tl, sg, 'FontSize', 11, 'FontWeight','bold');

        % Add ONE colorbar for the entire layout (attach to last axes)
        axLast = gca;
        cb = colorbar(axLast, 'eastoutside');
        if strcmp(powerScale,'db')
            cb.Label.String = 'Power (dB)';
        else
            cb.Label.String = 'Power (a.u.)';
        end

        % ---- Save ----
        outPng = fullfile(outDir, sprintf('SpecRaster_Evt%03d.png', e));
        exportgraphics(f, outPng, 'Resolution', 220);
        close(f);
        fprintf('Saved %s spectrogram: %s\n', tag, outPng);
    end
end

function [P, F, T] = computeSpec(x)
    % Compute single-channel spectrogram limited to fRangeHz.
    % Window/overlap in samples
    wSamp = max(8, round(winMs * sfx));
    oSamp = max(0, min(wSamp-1, round(overlapFrac * wSamp)));
    if isempty(nfftOpt)
        nfft = 2^nextpow2(max(256, wSamp)); % guard decent freq resolution
    else
        nfft = nfftOpt;
    end

    [S, F, T] = spectrogram(x(:), hamming(wSamp,'periodic'), oSamp, nfft, sfx);
    P = abs(S).^2; % linear power

    % keep only desired frequency band
    m = F >= fRangeHz(1) & F <= fRangeHz(2);
    F = F(m);
    P = P(m, :);
end

function [ok, s0, s1] = getAnchoredWindow(rowXL)
    ok = false; s0 = 1; s1 = 1;

    s0_ev = round(onSamp(rowXL));
    s1_ev = round(offSamp(rowXL));
    if ~(isfinite(s0_ev) && isfinite(s1_ev) && s1_ev > s0_ev), return; end

    switch anchorMode
        case "midpoint"
            anchor = round((s0_ev + s1_ev)/2);
        otherwise % "firstChMax"
            ancMid  = round((s0_ev + s1_ev)/2);
            s0a     = max(1, ancMid - HWanchor);
            s1a     = min(nSamp, ancMid + HWanchor);
            refCh   = chList(1);
            yseg0   = double(mf.d(refCh, s0a:s1a)) * scaleVec(refCh);
            if isempty(yseg0) || all(~isfinite(yseg0)), return; end
            [~, k_rel] = max(yseg0); % positive peak only
            anchor = s0a + k_rel - 1;
    end

    s0 = anchor - HWwin;
    s1 = anchor + HWwin;
    if s0 < 1 || s1 > nSamp, return; end
    ok = true;
end

function evts = parseEvtNumsFromPngs(dirpath)
    L = dir(fullfile(dirpath, '*.png'));
    evts = [];
    for k = 1:numel(L)
        m = regexp(L(k).name, 'Evt(\d+)', 'tokens', 'once');
        if ~isempty(m)
            ev = str2double(m{1});
            if isfinite(ev), evts(end+1) = ev; end %#ok<AGROW>
        end
    end
    evts = sort(unique(evts));
end

end
