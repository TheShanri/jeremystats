function SolidSputterAvgStack(inputFolder, dataMatPath, varargin)

p = inputParser;
p.addRequired('inputFolder', @(s)ischar(s)||isstring(s));
p.addRequired('dataMatPath', @(s)ischar(s)||isstring(s));
p.addParameter('halfWidthMs', 30e-3, @(x)isfinite(x)&&x>0);
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x)&&x>0);
p.addParameter('peakPolarity','abs', @(s) any(strcmpi(s,{'abs','pos','neg'})));
p.addParameter('align','midpoint', @(s) any(strcmpi(s,{'peak','midpoint'})));
p.addParameter('excelPath',"", @(s)ischar(s)||isstring(s));
p.addParameter('saveDir',"", @(s)ischar(s)||isstring(s));
p.addParameter('channelIndices', [], @(v) isempty(v) || (isnumeric(v) && all(v>=1)));
p.addParameter('maxEventsPerGroup', [], @(x) isempty(x) || (isscalar(x) && x>0));
p.parse(inputFolder, dataMatPath, varargin{:});

inputFolder     = string(p.Results.inputFolder);
dataMatPath     = string(p.Results.dataMatPath);
halfWidthMs     = p.Results.halfWidthMs;
scaleToMicroV   = p.Results.scaleToMicroV;
peakPolarity    = lower(string(p.Results.peakPolarity));
alignMode       = lower(string(p.Results.align));
excelPath       = string(p.Results.excelPath);
saveDir         = string(p.Results.saveDir);
channelIndices  = p.Results.channelIndices;
maxEventsPerGrp = p.Results.maxEventsPerGroup;

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

assert(isfile(dataMatPath), 'Data MAT not found: %s', dataMatPath);
mf = matfile(dataMatPath);
try sfx = mf.sfx; catch, error('Missing "sfx" in data MAT.'); end
nRowsAll = size(mf,'d',1);
nSamp    = size(mf,'d',2);
try kept_channels = mf.kept_channels; catch, kept_channels = []; end

if isempty(channelIndices)
    chList = 1:nRowsAll;
else
    chList = channelIndices(:).';
    chList = chList(chList>=1 & chList<=nRowsAll);
end
nCh = numel(chList);

if saveDir == "", outDir = inputFolder; else, outDir = char(saveDir); end
if ~exist(outDir,'dir'), mkdir(outDir); end

HW = max(1, round(halfWidthMs * sfx));
tRelSamples = -HW:HW;
tRelMs = (tRelSamples / sfx) * 1e3;
winN = numel(tRelSamples);

T = readtable(excelPath, 'ReadVariableNames', true);
if width(T) < 2, error('Excel must have at least 2 columns: [startIdx, endIdx].'); end
startIdxCol = T{:,1};
endIdxCol   = T{:,2};
if ~isnumeric(startIdxCol) || ~isnumeric(endIdxCol)
    error('First two columns must be numeric sample indices.');
end
NrowsXL = height(T);

evtSOL = unique(parseEvtNumsFromPngs(solidDir));
evtSPU = unique(parseEvtNumsFromPngs(sputterDir));
if ~isempty(maxEventsPerGrp)
    evtSOL = evtSOL(1:min(end, maxEventsPerGrp));
    evtSPU = evtSPU(1:min(end, maxEventsPerGrp));
end

[muSOL, seSOL, usedSOL] = avgForGroup(evtSOL, 'SOLID');
[muSPU, seSPU, usedSPU] = avgForGroup(evtSPU, 'SPUTTER');

alignLabel = tern(alignMode=="midpoint","midpoint",sprintf('peak(%s)',peakPolarity));

plotStack(muSOL, seSOL, 'SOLID', numel(usedSOL), alignLabel);
plotStack(muSPU, seSPU, 'SPUTTER', numel(usedSPU), alignLabel);

fprintf('Done. Outputs in: %s\n', outDir);

    function evts = parseEvtNumsFromPngs(dirpath)
        L = dir(fullfile(dirpath, '*.png'));
        evts = [];
        for k = 1:numel(L)
            nm = L(k).name;
            m = regexp(nm, 'Evt(\d+)', 'tokens', 'once');
            if ~isempty(m)
                ev = str2double(m{1});
                if isfinite(ev), evts(end+1) = ev; end %#ok<AGROW>
            end
        end
    end

    function [MU, SE, usedEvents] = avgForGroup(evtList, tag)
        if isempty(evtList)
            MU = []; SE = []; usedEvents = [];
            warning('%s: no events.', tag);
            return;
        end

        MU = nan(nCh, winN);
        SE = nan(nCh, winN);
        usedEvents = [];
        stacks = cell(nCh,1);
        for i=1:nCh, stacks{i} = []; end

        nBad = 0;
        for ii = 1:numel(evtList)
            e = evtList(ii);
            rowXL = e + 1;
            if rowXL < 1 || rowXL > NrowsXL
                nBad = nBad+1; continue;
            end
            s0_ev = max(1, round(startIdxCol(rowXL)));
            s1_ev = min(nSamp, round(endIdxCol(rowXL)));
            if ~isfinite(s0_ev) || ~isfinite(s1_ev) || s1_ev<=s0_ev
                nBad = nBad+1; continue;
            end

            if alignMode == "midpoint"
                anchorMid = round((s0_ev + s1_ev)/2);
            end

            okAnyCh = false;
            for k = 1:nCh
                ch = chList(k);

                if alignMode == "midpoint"
                    anchor = anchorMid;
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

                s0 = anchor - HW; s1 = anchor + HW;
                if s0 < 1 || s1 > nSamp, continue; end

                y = double(mf.d(ch, s0:s1)) * scaleToMicroV;
                if any(~isfinite(y)), continue; end

                stacks{k}(end+1, :) = y; %#ok<AGROW>
                okAnyCh = true;
            end

            if okAnyCh
                usedEvents(end+1) = e; %#ok<AGROW>
            end
        end

        if nBad>0
            fprintf('%s: skipped %d event(s) due to bad/missing indices/out-of-bounds.\n', tag, nBad);
        end
        fprintf('%s: used %d/%d events.\n', tag, numel(usedEvents), numel(evtList));

        for k = 1:nCh
            nUsedCh = size(stacks{k},1);
            if nUsedCh > 0
                MU(k,:) = mean(stacks{k}, 1, 'omitnan');
                SE(k,:) = std(stacks{k}, 0, 1, 'omitnan') ./ sqrt(nUsedCh);
            end
        end
    end

    function plotStack(MU, SE, tag, nEvents, alignLabel)
        if isempty(MU)
            warning('%s: no data to plot.', tag);
            return;
        end
        maxAbs = max(abs([MU(:); (MU(:)+SE(:)); (MU(:)-SE(:))]), [], 'omitnan');
        if ~isfinite(maxAbs) || maxAbs==0, maxAbs = 1; end
        pad = 0.05;
        span = (1+pad) * maxAbs;
        yL = span * [-1 1];

        nRowsGrid = nCh;
        perRowPx = 90; basePx = 200; maxPx = 5000;
        figH = min(maxPx, basePx + perRowPx * nRowsGrid);
        f = figure('Color','w','Position',[60 60 900 figH],'Visible','off');
        tl = tiledlayout(f, nRowsGrid, 1, 'Padding','compact','TileSpacing','compact');

        for k = 1:nCh
            nexttile(tl); hold on; box on; grid on;
            mu = MU(k,:); se = SE(k,:);
            if any(isfinite(mu))
                shadedMean(tRelMs, mu, se);
                xline(0,'--k','LineWidth',0.8); yline(0,':','Color',[0.7 0.7 0.7]);
            end
            ylim(yL);
            ch = chList(k);
            ttlTxt = localTitle(ch, kept_channels);
            title(ttlTxt,'FontSize',8);
            ax = gca; ax.FontSize = 8;
            if k < nCh, ax.XTickLabel = []; else, xlabel('ms'); end
            ylabel('\muV');
        end

        sg = sprintf('%s | align: %s | Win: \\pm%.1f ms | nEvents=%d | yLim=\\pm%.1f \\muV', ...
            tag, alignLabel, 1e3*HW/sfx, nEvents, (1+pad)*maxAbs);
        sgtitle(tl, sg, 'FontSize',12,'FontWeight','bold');

        outPng = fullfile(outDir, sprintf('AvgStack_%s_align-%s_HW%ds_%dms_rows-only_uV_fixedY.png', ...
            tag, strrep(alignLabel,'(','_'), HW, round(1e3*HW/sfx)));
        exportgraphics(f, outPng, 'Resolution', 220);
        close(f);

        statsPath = fullfile(outDir, sprintf('AvgStack_%s_stats.mat', tag));
        save(statsPath, 'MU','SE','tRelMs','chList','kept_channels','scaleToMicroV','halfWidthMs','sfx','alignLabel','nEvents');
        fprintf('Saved: %s\n', outPng);
        fprintf('Saved: %s\n', statsPath);
    end

    function shadedMean(x, mu, se)
        if isempty(mu) || all(~isfinite(mu)), return; end
        yu = mu + se; yl = mu - se;
        xp = [x, fliplr(x)];
        yp = [yu, fliplr(yl)];
        patch('XData',xp,'YData',yp,'FaceColor',[0.3 0.3 0.9],'FaceAlpha',0.25,'EdgeColor','none','HandleVisibility','off');
        plot(x, mu, 'LineWidth', 1.8);
    end

    function s = tern(cond, a, b)
        if cond, s = a; else, s = b; end
    end

    function ttl = localTitle(rowIdx, kept)
        if ~isempty(kept)
            ttl = sprintf('row %d (CSC%d)', rowIdx, kept(rowIdx));
        else
            ttl = sprintf('row %d', rowIdx);
        end
    end

end
