function EventStacks_AmpWidth_Avg(inputFolder, dataMatPath, varargin)
% Build SOLID/SPUTTER per-channel averaged stacks with amplitude & half-width stats.

% ---------- Args ----------
p = inputParser;
p.addRequired('inputFolder', @(s)ischar(s)||isstring(s));
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));

% Data / channels / scaling (assume µV unless you pass a scale)
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x)&&x>0);

% Alignment & windows
p.addParameter('align','midpoint', @(s) any(strcmpi(s,{'midpoint','peak'})));
p.addParameter('peakPolarity','abs', @(s) any(strcmpi(s,{'abs','pos','neg'})));
p.addParameter('halfWidthMs', 30e-3, @(x)isfinite(x)&&x>0);     % ± window for averaging/plotting
p.addParameter('metricHalfWidthMs', 5e-3, @(x)isfinite(x)&&x>0);% ± window for amp/HW metrics

% Spreadsheet + mapping
p.addParameter('excelPath',"", @(s)ischar(s)||isstring(s));
p.addParameter('indexBase','auto', @(s) any(strcmpi(s,{'auto','zero','one'})));
p.addParameter('evtOffset',0, @(x)isscalar(x)&&isfinite(x));      % add to event index to get Excel row
p.addParameter('maxEventsPerGroup', [], @(x) isempty(x) || (isscalar(x) && x>0));

% Output + y-axis
p.addParameter('saveDir',"", @(s)ischar(s)||isstring(s));
p.addParameter('tag','ALL', @(s)ischar(s)||isstring(s));
p.addParameter('yLimMicroV', [], @(x) isempty(x) || (isscalar(x) && x>0)); % if set: use ±this value everywhere
p.addParameter('yRobustPct', 99.5, @(x) isfinite(x) && x>0 && x<100);      % robust percentile if auto
p.addParameter('yPadFrac', 0.10, @(x) isfinite(x) && x>=0 && x<=0.5);      % headroom

p.parse(inputFolder, dataMatPath, varargin{:});
inputFolder     = string(p.Results.inputFolder);
dataMatPath     = string(p.Results.dataMatPath);
channelIndices  = p.Results.channelIndices;
scaleToMicroV   = p.Results.scaleToMicroV;

alignMode       = lower(string(p.Results.align));
peakPolarity    = lower(string(p.Results.peakPolarity));
halfWidthMs     = p.Results.halfWidthMs;
metricHWms      = p.Results.metricHalfWidthMs;

excelPath       = string(p.Results.excelPath);
indexBase       = lower(string(p.Results.indexBase));
evtOffset       = p.Results.evtOffset;
maxEventsPerGrp = p.Results.maxEventsPerGroup;

saveDir         = string(p.Results.saveDir);
tagStr          = string(p.Results.tag);
yLimMicroV      = p.Results.yLimMicroV;
yRobustPct      = p.Results.yRobustPct;
yPadFrac        = p.Results.yPadFrac;

% ---------- Layout (Solid/Sputter folders + Excel) ----------
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

if saveDir == "", outDir = inputFolder; else, outDir = char(saveDir); end
if ~exist(outDir,'dir'), mkdir(outDir); end

% ---------- Windows ----------
HWdisp = max(1, round(halfWidthMs * sfx));     % averaging/plot window (±)
HWmet  = max(1, round(metricHWms  * sfx));     % metric window (±)
tRelSamp = -HWdisp:HWdisp;
tRelMs   = (tRelSamp / sfx) * 1e3;
winN     = numel(tRelSamp);

fprintf('EventStacks_AmpWidth (Avg): sfx=%.1f Hz | plot ±%.1f ms | metrics ±%.1f ms | align=%s\n', ...
        sfx, 1e3*HWdisp/sfx, 1e3*HWmet/sfx, alignMode);

% ---------- Read spreadsheet -> on/off in samples ----------
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

% ---------- Event lists from folder PNG names ----------
evtSOL = unique(parseEvtNumsFromPngs(solidDir));
evtSPU = unique(parseEvtNumsFromPngs(sputterDir));
fprintf('Found %d SOLID events, %d SPUTTER events from filenames.\n', numel(evtSOL), numel(evtSPU));
if ~isempty(maxEventsPerGrp)
    evtSOL = evtSOL(1:min(end, maxEventsPerGrp));
    evtSPU = evtSPU(1:min(end, maxEventsPerGrp));
end

% ---------- Build stats for both groups ----------
[SOL, robSOL] = avgForGroup(evtSOL, 'SOLID');
[SPU, robSPU] = avgForGroup(evtSPU, 'SPUTTER');

% ---------- Global y-limit across BOTH figures ----------
if isempty(yLimMicroV)
    rob = max([robSOL, robSPU, 1]);
    yMax = (1 + yPadFrac) * rob;
else
    yMax = yLimMicroV;
end
yL_global = [-yMax, +yMax];
fprintf('Global y-limit (both figs): ±%.1f µV (%s)\n', yMax, tern(isempty(yLimMicroV),'robust','fixed'));

% ---------- Plot & save ----------
plotStack(SOL, 'SOLID', yL_global);
plotStack(SPU, 'SPUTTER', yL_global);

fprintf('Done. Outputs in: %s\n', outDir);

% ===================== helpers =====================

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

function [G, robAll] = avgForGroup(evtList, tag)
% Returns structure G with fields per channel:
%   MU (1xwinN), SE (1xwinN), nUsed, ampMean, ampSD, hwMean, hwSD, usedEvents
% Also returns robAll = robust |signal| percentile for y-lim suggestion.

    G.MU  = nan(nCh, winN);
    G.SE  = nan(nCh, winN);
    G.n   = zeros(nCh,1);
    G.ampMean = nan(nCh,1);
    G.ampSD   = nan(nCh,1);
    G.hwMean  = nan(nCh,1);
    G.hwSD    = nan(nCh,1);
    G.usedEvents = [];
    G.tRelMs  = tRelMs; %#ok<STRNU>
    robAll = 0;

    if isempty(evtList)
        warning('%s: no events.', tag);
        return;
    end

    stacks = cell(nCh,1);   % waveforms per channel (rows=events)
    amps   = cell(nCh,1);   % per-event amplitudes (µV)
    hws    = cell(nCh,1);   % per-event half-widths (ms)
    for i=1:nCh, stacks{i} = []; amps{i} = []; hws{i} = []; end

    nBad = 0;
    for ii = 1:numel(evtList)
        e = evtList(ii);
        % Map event id -> spreadsheet row
        rowXL = e + evtOffset;
        if rowXL < 1 || rowXL > NrowsXL
            alt = e;
            if alt >= 1 && alt <= NrowsXL
                rowXL = alt;
            else
                nBad = nBad + 1;
                continue;
            end
        end

        s0_ev = max(1, round(onSamp(rowXL)));
        s1_ev = min(nSamp, round(offSamp(rowXL)));
        if ~isfinite(s0_ev) || ~isfinite(s1_ev) || s1_ev <= s0_ev
            nBad = nBad + 1; continue;
        end

        % Shared midpoint anchor unless aligning by per-channel peak
        ancMid = round((s0_ev + s1_ev)/2);

        okAnyCh = false;
        for k = 1:nCh
            ch = chList(k);
            sc = scaleToMicroV; if numel(sc)>1, sc = sc(ch); end

            % per-channel anchor
            if alignMode == "midpoint"
                anchor = ancMid;
            else
                yseg = double(mf.d(ch, s0_ev:s1_ev));
                if any(~isfinite(yseg)), continue; end
                switch peakPolarity
                    case "pos", [~, kp] = max(yseg);
                    case "neg", [~, kp] = min(yseg);
                    otherwise,  [~, kp] = max(abs(yseg));
                end
                anchor = s0_ev + kp - 1;
            end

            % Averaging window
            s0 = anchor - HWdisp; s1 = anchor + HWdisp;
            if s0 < 1 || s1 > nSamp, continue; end
            y = double(mf.d(ch, s0:s1)) * sc;    % µV
            if any(~isfinite(y)), continue; end
            stacks{k}(end+1,:) = y; %#ok<AGROW>
            okAnyCh = true;

            % Robust y-lim accumulator
            p = prctile(abs(y), yRobustPct);
            if isfinite(p) && p > robAll, robAll = p; end

            % Metrics window (±metric)
            s0m = max(1, anchor - HWmet);
            s1m = min(nSamp, anchor + HWmet);
            ym  = double(mf.d(ch, s0m:s1m)) * sc;   % µV
            if numel(ym) >= 3 && all(isfinite(ym))
                [mx, kMax] = max(ym);
                [mn, kMin] = min(ym);
                if abs(mn) > abs(mx)
                    sgn = -1; amp = abs(mn); pkRel = kMin;
                else
                    sgn = +1; amp = abs(mx); pkRel = kMax;
                end
                h = 0.5*amp; sig = sgn*ym;

                % left crossing
                kL = pkRel;
                while kL > 1 && sig(kL) >= h, kL = kL - 1; end
                if kL >= 1 && (kL+1) <= numel(sig)
                    left_ip = kL + (h - sig(kL)) / (sig(kL+1) - sig(kL));
                else
                    left_ip = NaN;
                end
                % right crossing
                kR = pkRel; L = numel(sig);
                while kR < L && sig(kR) >= h, kR = kR + 1; end
                if (kR-1) >= 1 && kR <= L
                    right_ip = (kR-1) + (h - sig(kR-1)) / (sig(kR) - sig(kR-1));
                else
                    right_ip = NaN;
                end

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

        if okAnyCh
            G.usedEvents(end+1) = e; %#ok<AGROW>
            if numel(G.usedEvents) <= 5
                fprintf('%s evt %d -> row %d | on=%d off=%d (%.2f ms) | anchorMid=%d\n', ...
                    tag, e, rowXL, s0_ev, s1_ev, 1e3*(s1_ev - s0_ev + 1)/sfx, ancMid);
            end
        end
    end

    if nBad>0
        fprintf('%s: skipped %d event(s) due to bad/missing indices/out-of-bounds.\n', tag, nBad);
    end
    fprintf('%s: used %d/%d events.\n', tag, numel(G.usedEvents), numel(evtList));

    % Per-channel aggregate stats
    for k = 1:nCh
        X = stacks{k};
        nUsed = size(X,1);
        G.n(k) = nUsed;
        if nUsed > 0
            G.MU(k,:) = mean(X, 1, 'omitnan');
            G.SE(k,:) = std( X, 0, 1, 'omitnan') ./ sqrt(nUsed);
        end

        a = amps{k}; w = hws{k};
        if ~isempty(a), G.ampMean(k) = mean(a, 'omitnan'); G.ampSD(k) = std(a, 0, 'omitnan'); end
        if ~isempty(w), G.hwMean(k)  = mean(w, 'omitnan'); G.hwSD(k)  = std(w,  0, 'omitnan'); end
    end

    % Save stats MAT for this group
    alignLabel = tern(alignMode=="midpoint","midpoint",sprintf('peak(%s)',peakPolarity));
    statsPath = fullfile(outDir, sprintf('AvgStack_%s_stats.mat', tag));
    chList_local = chList; %#ok<NASGU>
    scale_local  = scaleToMicroV; %#ok<NASGU>
    save(statsPath, 'tRelMs','chList_local','kept_channels','scale_local','halfWidthMs','metricHWms','sfx', ...
                    'alignLabel','G');
    fprintf('Saved: %s\n', statsPath);
end

function plotStack(G, tag, yL)
    if isempty(G) || all(all(isnan(G.MU))), warning('%s: no data to plot.', tag); return; end

    nRowsGrid = nCh;
    perRowPx = 90; basePx = 220; maxPx = 5200;
    figH = min(maxPx, basePx + perRowPx * nRowsGrid);
    f = figure('Color','w','Position',[60 60 980 figH],'Visible','off');
    tl = tiledlayout(f, nRowsGrid, 1, 'Padding','compact','TileSpacing','compact');

    for k = 1:nCh
        mu = G.MU(k,:); se = G.SE(k,:);
        nexttile(tl); hold on; box on; grid on;

        if any(isfinite(mu))
            yu = mu + se; yl = mu - se;
            xp = [tRelMs, fliplr(tRelMs)];
            yp = [yu,      fliplr(yl)];
            patch('XData',xp,'YData',yp,'FaceColor',[0.3 0.3 0.9],'FaceAlpha',0.25,'EdgeColor','none','HandleVisibility','off');
            plot(tRelMs, mu, 'LineWidth', 1.8);
        end

        xline(0,'--k','LineWidth',0.8); yline(0,':','Color',[0.7 0.7 0.7]);
        ylim(yL);

        % Title (includes amp/HW mean±SD)
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
        title(ttlTxt, 'FontSize',9, 'FontWeight','normal');

        ax = gca; ax.FontSize = 8;
        if k < nCh, ax.XTickLabel = []; else, xlabel('ms'); end
        ylabel('\muV');
    end

    alignLabel = tern(alignMode=="midpoint","midpoint",sprintf('peak(%s)',peakPolarity));
    sg = sprintf('%s  |  align: %s  |  avg window: \\pm%.1f ms  |  metrics: \\pm%.1f ms  |  channels=%d  |  %s', ...
                 tag, alignLabel, 1e3*HWdisp/sfx, 1e3*HWmet/sfx, nCh, tagStr);
    sgtitle(tl, sg, 'FontSize',12,'FontWeight','bold');

    outPng = fullfile(outDir, sprintf('AvgStack_%s_align-%s_HW%ds_%dms_globalY.png', ...
        tag, regexprep(alignLabel,'[^a-zA-Z0-9]+','_'), HWdisp, round(1e3*HWdisp/sfx)));
    exportgraphics(f, outPng, 'Resolution', 220);
    close(f);
    fprintf('Saved: %s\n', outPng);
end

function s = tern(cond, a, b)
    if cond, s = a; else, s = b; end
end

end
