function VoltageRaster_EventsAvg(inputFolder, dataMatPath, varargin)
% AvgWave_SolidSputter
% Build ONE averaged stack plot per group (SOLID, SPUTTER):
%   - Anchor per-event on FIRST channel's positive peak within ±5 ms of midpoint
%   - Window ±20 ms (default)
%   - Average across events per channel (mean ± SEM)
%   - Compute per-event amplitude (positive peak) and half-width-at-half-max (HWHM) per channel
%   - Titles include n and amp/HW stats; global y-limit shared across both figures
%
% INPUTS
%   inputFolder   : contains "Solid"/"Sputter" subfolders and the Excel sheet
%   dataMatPath   : MAT with fields d [nRows x nSamp], sfx (Hz), kept_channels (optional)
%
% NAME-VALUE OPTIONS
%   'excelPath'         : path to Excel (auto-detected as *.xlsx in inputFolder if omitted)
%   'channelIndices'    : rows (channels) to include; default = all rows of d
%   'scaleToMicroV'     : scalar or per-row vector to scale raw -> µV (default 1)
%   'displayHalfWidthMs': ±ms for plotting window (default 20e-3)
%   'metricHalfWidthMs' : ±ms for metrics window (default 5e-3)
%   'anchorHalfWidthMs' : ±ms to search first-ch max around midpoint (default 5e-3)
%   'indexBase'         : 'auto' | 'zero' | 'one' (default 'auto') for Excel indexing
%   'evtOffset'         : integer offset to map event# -> Excel row (default 0)
%   'maxEventsPerGroup' : optional cap on events used per group
%   'saveDir'           : output directory (default: inputFolder)
%   'tag'               : text tag to append in titles (default 'ALL')
%   'yLimMicroV'        : fixed ± y-limit; if empty, robust auto across both groups
%   'yRobustPct'        : percentile for robust auto y-limit (default 99.5)
%   'yPadFrac'          : fractional headroom (default 0.12)
%
% OUTPUT
%   Saves:
%     AvgStack_SOLID_...png
%     AvgStack_SPUTTER_...png

% ---------- Parse ----------
p = inputParser;
p.addRequired('inputFolder', @(s)ischar(s)||isstring(s));
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));

p.addParameter('excelPath',"", @(s)ischar(s)||isstring(s));
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('scaleToMicroV', 1, @(x)isnumeric(x)&&all(isfinite(x))&&all(x>0));

p.addParameter('displayHalfWidthMs', 20e-3, @(x)isfinite(x)&&x>0);
p.addParameter('metricHalfWidthMs',   5e-3, @(x)isfinite(x)&&x>0);
p.addParameter('anchorHalfWidthMs',   5e-3, @(x)isfinite(x)&&x>0);

p.addParameter('excelIndexBase','auto', @(s) any(strcmpi(s,{'auto','zero','one'})));
p.addParameter('evtOffset',0, @(x)isscalar(x)&&isfinite(x));
p.addParameter('maxEventsPerGroup', [], @(x) isempty(x) || (isscalar(x) && x>0));

p.addParameter('saveDir','', @(s)ischar(s)||isstring(s));
p.addParameter('tag','ALL', @(s)ischar(s)||isstring(s));
p.addParameter('yLimMicroV', [], @(x) isempty(x) || (isscalar(x) && x>0));
p.addParameter('yRobustPct', 99.5, @(x) isfinite(x) && x>0 && x<100);
p.addParameter('yPadFrac', 0.12, @(x) isfinite(x) && x>=0 && x<=0.5);

p.parse(inputFolder, dataMatPath, varargin{:});

inputFolder     = string(p.Results.inputFolder);
dataMatPath     = string(p.Results.dataMatPath);
excelPath       = string(p.Results.excelPath);
channelIndices  = p.Results.channelIndices;
scaleToMicroV   = p.Results.scaleToMicroV;

dispHWms        = p.Results.displayHalfWidthMs;
metricHWms      = p.Results.metricHalfWidthMs;
anchorHWms      = p.Results.anchorHalfWidthMs;

indexBase       = lower(string(p.Results.excelIndexBase));
evtOffset       = p.Results.evtOffset;
maxPerGroup     = p.Results.maxEventsPerGroup;

saveDir         = string(p.Results.saveDir);
tagStr          = string(p.Results.tag);
yLimMicroV      = p.Results.yLimMicroV;
yRobustPct      = p.Results.yRobustPct;
yPadFrac        = p.Results.yPadFrac;

% ---------- Layout ----------
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

% ---------- Data ----------
assert(isfile(dataMatPath), 'Data MAT not found: %s', dataMatPath);
mf = matfile(dataMatPath);
try sfx = mf.sfx; catch, error('Missing "sfx" in data MAT.'); end
nRowsAll = size(mf,'d',1);
nSamp    = size(mf,'d',2);
try kept_channels = mf.kept_channels; catch, kept_channels = []; end %#ok<NASGU>

if isempty(channelIndices)
    chList = 1:nRowsAll;
else
    chList = channelIndices(:).';
    chList = chList(chList>=1 & chList<=nRowsAll);
end
nCh = numel(chList);

% scale vector
if numel(scaleToMicroV)==1
    scaleVec = repmat(scaleToMicroV, nRowsAll, 1);
else
    assert(numel(scaleToMicroV)>=nRowsAll, 'scaleToMicroV must be scalar or >= nRowsAll.');
    scaleVec = scaleToMicroV(:);
end

% ---------- Windows & axes ----------
HWdisp    = max(1, round(dispHWms   * sfx));
HWmet     = max(1, round(metricHWms * sfx));
HWanchor  = max(1, round(anchorHWms * sfx));
tRelSamp  = -HWdisp:HWdisp;
tRelMs    = (tRelSamp / sfx) * 1e3;
winN      = numel(tRelSamp);
centerIdx = HWdisp+1;

% output dir
if saveDir=="", outDir = inputFolder; else, outDir = char(saveDir); end
if ~exist(outDir,'dir'), mkdir(outDir); end

fprintf('AvgWave_SolidSputter: sfx=%.1f Hz | window ±%.1f ms | metrics ±%.1f ms | anchor search ±%.1f ms | channels=%d\n', ...
    sfx, 1e3*HWdisp/sfx, 1e3*HWmet/sfx, 1e3*HWanchor/sfx, nCh);

% ---------- Excel -> sample bounds ----------
T = readtable(excelPath,'ReadVariableNames',true);
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
    assert(width(T)>=2,'Excel must have [on_samp, off_samp] or [on_sec, off_sec].');
    onSamp  = double(T{:,1});
    offSamp = double(T{:,2});
end

switch indexBase
    case "zero", onSamp = onSamp+1; offSamp = offSamp+1;
    case "auto"
        if any(onSamp < 1 | offSamp < 1 | onSamp==0 | offSamp==0)
            onSamp = onSamp+1; offSamp = offSamp+1;
        end
    case "one"
        % no-op
end

NrowsXL = numel(onSamp);
onSamp  = max(1, min(onSamp,  nSamp));
offSamp = max(1, min(offSamp, nSamp));

% ---------- Events by PNG names ----------
evtSOL = parseEvtNumsFromPngs(solidDir);
evtSPU = parseEvtNumsFromPngs(sputterDir);
fprintf('Found events: SOLID=%d, SPUTTER=%d (from filenames).\n', numel(evtSOL), numel(evtSPU));

if ~isempty(maxPerGroup)
    evtSOL = evtSOL(1:min(end, maxPerGroup));
    evtSPU = evtSPU(1:min(end, maxPerGroup));
end

% ---------- Build group stats ----------
[SOL, robSOL] = avgForGroup(evtSOL, 'SOLID');
[SPU, robSPU] = avgForGroup(evtSPU, 'SPUTTER');

% ---------- Global y-limit across BOTH figures ----------
if isempty(yLimMicroV)
    yMaxSOL = computeYMax(SOL);
    yMaxSPU = computeYMax(SPU);
    rob = max([robSOL, robSPU, yMaxSOL, yMaxSPU, 10]); % >=10 µV headroom floor
    yMax = (1 + yPadFrac) * rob;
else
    yMax = yLimMicroV;
end
yL = [-yMax, +yMax];
fprintf('Global y-limit: ±%.1f µV (%s)\n', yMax, tern(isempty(yLimMicroV),'auto','fixed'));

% ---------- Plot & save (one figure per group) ----------
plotStack(SOL, 'SOLID', yL);
plotStack(SPU, 'SPUTTER', yL);
fprintf('Done. Outputs in: %s\n', outDir);

% ======================================================================
%                                HELPERS
% ======================================================================

function evts = parseEvtNumsFromPngs(dirpath)
    L = dir(fullfile(dirpath,'*.png'));
    evts = [];
    for k = 1:numel(L)
        m = regexp(L(k).name,'Evt(\d+)','tokens','once');
        if ~isempty(m)
            ev = str2double(m{1});
            if isfinite(ev), evts(end+1) = ev; end %#ok<AGROW>
        end
    end
    evts = sort(unique(evts));
end

function yMax = computeYMax(G)
% Max of |mean±SE| and 3*SD safety from per-event amps (avoid clipping)
    if isempty(G) || all(all(isnan(G.MU))), yMax = 0; return; end
    mm = max(abs([G.MU(:)+G.SE(:); G.MU(:)-G.SE(:)]), [], 'omitnan');
    as = max(G.ampMean + 3*G.ampSD, [], 'omitnan');
    yMax = max([mm, as, 0], [], 'omitnan');
    if ~isfinite(yMax) || yMax <= 0, yMax = 0; end
end

function [G, robAll] = avgForGroup(evtList, tag)
% Aggregate per channel across events aligned to FIRST-channel positive peak
% Returns:
%   G.MU (nCh x winN), G.SE (nCh x winN), G.n (nCh x 1)
%   G.ampMean/SD, G.hwMean/SD (per-event metrics), G.usedEvents
%   robAll: robust |signal| percentile across all y (for y-limit suggestion)

    G.MU = nan(nCh, winN);
    G.SE = nan(nCh, winN);
    G.n  = zeros(nCh,1);
    G.ampMean = nan(nCh,1); G.ampSD = nan(nCh,1);
    G.hwMean  = nan(nCh,1); G.hwSD  = nan(nCh,1);
    G.usedEvents = [];
    robAll = 0;

    if isempty(evtList)
        warning('%s: no events.', tag); return;
    end

    stacks = cell(nCh,1);
    amps   = cell(nCh,1);
    hws    = cell(nCh,1);
    for i=1:nCh, stacks{i} = []; amps{i} = []; hws{i} = []; end

    refCh = chList(1); % FIRST channel anchors all channels

    nBad = 0;
    for ii = 1:numel(evtList)
        e = evtList(ii);
        rowXL = e + evtOffset;
        if rowXL < 1 || rowXL > NrowsXL
            alt = e;
            if alt >= 1 && alt <= NrowsXL, rowXL = alt; else, nBad=nBad+1; continue; end
        end

        s0_ev = max(1, round(onSamp(rowXL)));
        s1_ev = min(nSamp, round(offSamp(rowXL)));
        if ~isfinite(s0_ev) || ~isfinite(s1_ev) || s1_ev <= s0_ev
            nBad=nBad+1; continue;
        end

        % Midpoint, then search ±HWanchor on FIRST channel for positive max
        ancMid = round((s0_ev + s1_ev)/2);
        s0a = max(1, ancMid - HWanchor);
        s1a = min(nSamp, ancMid + HWanchor);
        y0  = double(mf.d(refCh, s0a:s1a)) * scaleVec(refCh);
        if isempty(y0) || all(~isfinite(y0))
            nBad = nBad + 1; continue;
        end
        [~, krel] = max(y0);            % positive max (no abs, no min)
        anchor = s0a + krel - 1;

        okAny = false;
        for k = 1:nCh
            ch = chList(k);
            sc = scaleVec(ch);

            % display window centered on common anchor
            s0 = anchor - HWdisp; s1 = anchor + HWdisp;
            if s0 < 1 || s1 > nSamp, continue; end
            y  = double(mf.d(ch, s0:s1)) * sc;
            if any(~isfinite(y)), continue; end
            stacks{k}(end+1,:) = y; %#ok<AGROW>
            okAny = true;

            % robust y-limit helper
            p = prctile(abs(y(:)), yRobustPct);
            if isfinite(p) && p > robAll, robAll = p; end

            % metrics around anchor (±HWmet) on raw (positive peak only)
            s0m = max(1, anchor - HWmet); s1m = min(nSamp, anchor + HWmet);
            ym  = double(mf.d(ch, s0m:s1m)) * sc;
            if numel(ym) >= 3 && all(isfinite(ym))
                [amp, pkRel] = max(ym);     % positive peak
                h = 0.5 * amp;
                % left crossing
                kL = pkRel;
                while kL > 1 && ym(kL) >= h, kL = kL - 1; end
                if kL >= 1 && (kL+1) <= numel(ym) && ym(kL) < h && ym(kL+1) >= h
                    left_ip = kL + (h - ym(kL)) / (ym(kL+1) - ym(kL));
                else, left_ip = NaN; end
                % right crossing
                kR = pkRel; Lm = numel(ym);
                while kR < Lm && ym(kR) >= h, kR = kR + 1; end
                if (kR-1) >= 1 && kR <= Lm && ym(kR-1) >= h && ym(kR) < h
                    right_ip = (kR-1) + (h - ym(kR-1)) / (ym(kR) - ym(kR-1));
                else, right_ip = NaN; end

                if isfinite(left_ip) && isfinite(right_ip) && right_ip > left_ip
                    hw_ms = (right_ip - left_ip) / sfx * 1e3;
                else
                    hw_ms = NaN;
                end
                amps{k}(end+1,1) = amp; %#ok<AGROW>
                hws{k}(end+1,1)  = hw_ms; %#ok<AGROW>
            else
                amps{k}(end+1,1) = NaN; %#ok<AGROW>
                hws{k}(end+1,1)  = NaN; %#ok<AGROW>
            end
        end

        if okAny
            G.usedEvents(end+1) = e; %#ok<AGROW>
            if numel(G.usedEvents) <= 5
                fprintf('%s evt %d -> row %d | on=%d off=%d (%.2f ms) | anchor=%d\n', ...
                    tag, e, rowXL, s0_ev, s1_ev, 1e3*(s1_ev-s0_ev+1)/sfx, anchor);
            end
        end
    end

    if nBad>0, fprintf('%s: skipped %d event(s) (bad/out-of-bounds/anchor fail).\n', tag, nBad); end
    fprintf('%s: used %d/%d events.\n', tag, numel(G.usedEvents), numel(evtList));

    % Aggregate per channel
    for k = 1:nCh
        X = stacks{k}; nUsed = size(X,1); G.n(k) = nUsed;
        if nUsed > 0
            G.MU(k,:) = mean(X, 1, 'omitnan');
            G.SE(k,:) = std( X, 0, 1, 'omitnan') ./ max(1,sqrt(nUsed)); % SEM
        end
        a = amps{k}; w = hws{k};
        if ~isempty(a), G.ampMean(k) = mean(a,'omitnan'); G.ampSD(k) = std(a,0,'omitnan'); end
        if ~isempty(w), G.hwMean(k)  = mean(w,'omitnan'); G.hwSD(k)  = std(w,0,'omitnan'); end
    end
end

function plotStack(G, tag, yL)
    if isempty(G) || all(all(isnan(G.MU))), warning('%s: no data.', tag); return; end
    nCols = 2; nRowsGrid = ceil(nCh / nCols);
    perRowPx = 120; basePx = 220; maxPx = 5200;
    figH = min(maxPx, basePx + perRowPx * nRowsGrid);
    f = figure('Color','w','Position',[60 60 1100 figH],'Visible','off');
    tl = tiledlayout(f, nRowsGrid, nCols, 'Padding','compact','TileSpacing','compact');

    % metric region (indices) within mean vector
    metStart = max(1, centerIdx - HWmet);
    metEnd   = min(winN, centerIdx + HWmet);
    Lmet     = metEnd - metStart + 1;

    for k = 1:nCh
        mu = G.MU(k,:); se = G.SE(k,:);
        nexttile(tl); hold on; box on; grid on;
        if any(isfinite(mu))
            yu = mu + se; yl = mu - se;
            xp = [tRelMs, fliplr(tRelMs)]; yp = [yu, fliplr(yl)];
            patch('XData',xp,'YData',yp,'FaceColor',[0.3 0.3 0.9],'FaceAlpha',0.25,...
                  'EdgeColor','none','HandleVisibility','off');
            plot(tRelMs, mu, 'LineWidth', 1.8);

            % indicators: positive-peak + HW on MEAN within metric window
            muMet = mu(metStart:metEnd);
            if numel(muMet) >= 3 && all(isfinite(muMet))
                [amp, pkRel] = max(muMet);
                h = 0.5 * amp;
                % left
                kL = pkRel;
                while kL > 1 && muMet(kL) >= h, kL = kL - 1; end
                if kL >=1 && (kL+1)<=Lmet && muMet(kL) < h && muMet(kL+1) >= h
                    left_ip = kL + (h - muMet(kL))/(muMet(kL+1)-muMet(kL));
                else, left_ip = NaN; end
                % right
                kR = pkRel;
                while kR < Lmet && muMet(kR) >= h, kR = kR + 1; end
                if (kR-1)>=1 && kR<=Lmet && muMet(kR-1) >= h && muMet(kR) < h
                    right_ip = (kR-1) + (h - muMet(kR-1))/(muMet(kR)-muMet(kR-1));
                else, right_ip = NaN; end

                if isfinite(left_ip) && isfinite(right_ip)
                    tPk_ms = ((metStart + pkRel  - 1) - centerIdx) / sfx * 1e3;
                    tL_ms  = ((metStart + left_ip - 1) - centerIdx) / sfx * 1e3;
                    tR_ms  = ((metStart + right_ip- 1) - centerIdx) / sfx * 1e3;

                    if tL_ms >= tRelMs(1) && tR_ms <= tRelMs(end)
                        xline(tL_ms,'-','Color',[0.85 0.10 0.10],'LineWidth',2.2,'HandleVisibility','off');
                        xline(tR_ms,'-','Color',[0.85 0.10 0.10],'LineWidth',2.2,'HandleVisibility','off');
                        plot([tL_ms tR_ms],[0 0],'-','Color',[0.85 0.10 0.10],'LineWidth',1.4,'HandleVisibility','off');
                    end
                    if tPk_ms >= tRelMs(1) && tPk_ms <= tRelMs(end)
                        plot(tPk_ms, amp, 'o','MarkerSize',4.5,'MarkerFaceColor',[0 0 0],...
                             'MarkerEdgeColor','none','HandleVisibility','off');
                    end
                end
            end
        end
        xline(0,'--k','LineWidth',0.9); yline(0,':','Color',[0.7 0.7 0.7]);
        ylim(yL);

        if ~isempty(kept_channels)
            chName = sprintf('row %d (CSC%d)', chList(k), kept_channels(chList(k)));
        else
            chName = sprintf('row %d', chList(k));
        end
        if isfinite(G.ampMean(k)) && isfinite(G.hwMean(k))
            ttlTxt = sprintf('%s | amp=%.1f\\pm%.1f \\muV | HW=%.2f\\pm%.2f ms | n=%d', ...
                chName, G.ampMean(k), G.ampSD(k), G.hwMean(k), G.hwSD(k), G.n(k));
        else
            ttlTxt = sprintf('%s | amp=NA | HW=NA | n=%d', chName, G.n(k));
        end
        title(ttlTxt, 'FontSize',9,'FontWeight','normal');
        ax = gca; ax.FontSize = 8;
        if k <= nCh - nCols, ax.XTickLabel = []; else, xlabel('ms'); end
        ylabel('\muV');
    end

    sg = sprintf('%s  | anchor: first-channel max (±%.1f ms) | display: \\pm%.1f ms | metrics: \\pm%.1f ms | channels=%d | events used=%d | %s', ...
         tag, 1e3*HWanchor/sfx, 1e3*HWdisp/sfx, 1e3*HWmet/sfx, nCh, numel(G.usedEvents), tagStr);
    sgtitle(tl, sg, 'FontSize',12,'FontWeight','bold');

    outPng = fullfile(outDir, sprintf('AvgStack_%s_anchor-max_disp%ds_met%ds_globalY.png', ...
        tag, HWdisp, HWmet));
    exportgraphics(f, outPng, 'Resolution', 220);
    close(f);
    fprintf('Saved: %s\n', outPng);
end

function s = tern(cond, a, b), if cond, s = a; else, s = b; end, end

end
