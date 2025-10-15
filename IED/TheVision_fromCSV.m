function TheVision_fromCSV(recDir, csvPath, varargin)
% Plot per-event multi-channel stacks using ONLY windows listed in CSV.
% Supports two CSV formats:
%  A) 'channels' = "2,4,8"; OR
%  B) 'channels' = numeric count, with extra columns (e.g. 'Unnamed: 5'..)
%     holding actual CSC numbers per event row.
%
% Name-Value:
%   'halfWidthMs', 'align', 'peakPolarity', 'scaleToMicroV','scaleToMV',
%   'saveDir', 'minCh', 'maxCh' (defaults match previous version)

% ---------- Parse ----------
p = inputParser;
p.addRequired('recDir', @(s)ischar(s)||isstring(s));
p.addRequired('csvPath', @(s)ischar(s)||isstring(s));
p.addParameter('halfWidthMs', 30e-3, @(x)isfinite(x)&&x>0);
p.addParameter('align','midpoint', @(s)any(strcmpi(s,{'midpoint','peak'})));
p.addParameter('peakPolarity','abs', @(s) any(strcmpi(s,{'abs','pos','neg'})));
p.addParameter('scaleToMicroV', 1, @(x)isfinite(x)&&x>0);
p.addParameter('scaleToMV', [], @(x)isempty(x)||(isfinite(x)&&x>0));
p.addParameter('saveDir','', @(s)ischar(s)||isstring(s));
p.addParameter('minCh', 6, @(x)isfinite(x)&&x>=0);
p.addParameter('maxCh', 8, @(x)isfinite(x)&&x>=0);
p.parse(recDir, csvPath, varargin{:});

recDir        = string(p.Results.recDir);
csvPath       = string(p.Results.csvPath);
halfWidthMs   = p.Results.halfWidthMs;
alignMode     = lower(string(p.Results.align));
peakPolarity  = lower(string(p.Results.peakPolarity));
scaleToMicroV = p.Results.scaleToMicroV;
scaleToMV     = p.Results.scaleToMV; % deprecated
saveDir       = string(p.Results.saveDir);
minCh         = p.Results.minCh;
maxCh         = p.Results.maxCh;

if ~isempty(scaleToMV)
    scaleToMicroV = scaleToMV * 1000; % mV -> µV
    warning('TheVision:DeprecatedArg', '''scaleToMV'' deprecated. Using scaleToMicroV=%g.', scaleToMicroV);
end
if ~isfile(csvPath), error('CSV not found: %s', csvPath); end

% ---------- Discover CSC files (even channels, sorted) ----------
files = dir(fullfile(recDir, 'CSC*.ncs'));
if isempty(files), error('No CSC*.ncs in %s', recDir); end
nums  = cellfun(@(s) sscanf(s,'CSC%d.ncs'), {files.name});
keep  = mod(nums,2)==0 & ~isnan(nums);
files = files(keep); nums = nums(keep);
[nums,ix] = sort(nums,'ascend'); files=files(ix);
cscNums = nums(:)'; nChan = numel(cscNums);

% ---------- Determine sample rate from first file ----------
FsVec = Nlx2MatCSC(fullfile(files(1).folder, files(1).name), [0 0 1 0 0], 0, 1, []);
if isempty(FsVec), error('Could not read sampling frequency from %s', files(1).name); end
sfx = double(FsVec(1));
fprintf('[info] sfx = %g Hz (from %s)\n', sfx, files(1).name);

% ---------- Load CSV ----------
T = readtable(csvPath, 'TextType', 'string');
needCols = {'sample_start','sample_end'};
for c = needCols
    if ~isfield(T, c{1}) && ~ismember(c{1}, T.Properties.VariableNames)
        error('CSV missing required column: %s', c{1});
    end
end
sample_start = double(T.sample_start);
sample_end   = double(T.sample_end);

% Identify "channels list" layout:
hasChanCol = ismember('channels', T.Properties.VariableNames);
chanIsStringList = false;
chanIsNumericWithExtras = false;

if hasChanCol
    % If channels is string (non-numeric) → list format
    if iscellstr(cellstr(T.channels)) || isstring(T.channels)
        % Detect if any row contains comma or space-separated numbers
        ex = T.channels( find(T.channels~="", 1, 'first') );
        if ~isempty(ex)
            % If it's purely numeric like "36" *without* separators,
            % treat as NOT a list.
            chanIsStringList = contains(ex, ",") || contains(ex, " ") || contains(ex, ";");
        end
    end
end

% Gather extra columns that likely hold channel IDs per row (numeric)
extraCols = T.Properties.VariableNames(~ismember(T.Properties.VariableNames, ...
    {'sample_start','sample_end','time_start_s','time_end_s','channels'}));
% Keep only those whose values look numeric
extraCols = extraCols( arrayfun(@(k) isnumeric(T.(extraCols{k})), 1:numel(extraCols)) );

% If channels not a string list, and we have extra numeric columns → numeric+extras format
if ~chanIsStringList && ~isempty(extraCols)
    chanIsNumericWithExtras = true;
end

% Function to get active CSC list for a row:
    function v = get_active_list(row)
        if chanIsStringList
            v = str2num_list(T.channels(row)); %#ok<ST2NM>
        elseif chanIsNumericWithExtras
            % concatenate numeric non-NaN entries across extraCols
            tmp = [];
            for cc = 1:numel(extraCols)
                val = T.(extraCols{cc})(row);
                if ~isnan(val), tmp(end+1) = double(val); end %#ok<AGROW>
            end
            v = unique(tmp); % CSC numbers
        else
            % Fallback: if channels is numeric but no extra columns, treat
            % as single channel id (unlikely, but prevents crash)
            if hasChanCol && ~isnan(double(T.channels(row)))
                v = double(T.channels(row));
            else
                v = [];
            end
        end
        % Filter to those we actually have on disk (even CSCs)
        if ~isempty(v)
            v = v(ismember(v, cscNums));
        end
    end

% Filter events by active channel count
actCounts = zeros(height(T),1);
for i=1:height(T)
    actCounts(i) = numel(get_active_list(i));
end
keepEvt = (actCounts>=minCh) & (actCounts<=maxCh);
evtIdx  = find(keepEvt);

if isempty(evtIdx)
    fprintf('No events within %d–%d channels.\n', minCh, maxCh);
    return;
end

% ---------- Output dir ----------
outDir = saveDir;
if outDir=="" || ~isfolder(outDir), outDir = recDir; end
fprintf('[info] will save PNGs to: %s\n', outDir);

% ---------- Constants ----------
HW   = max(1, round(halfWidthMs * sfx));
REC  = 512; % CSC block size

% ---------- Iterate events ----------
for eii = 1:numel(evtIdx)
    e = evtIdx(eii);
    evS = max(1, sample_start(e));
    evE = sample_end(e);
    if evE <= evS, fprintf('Evt %d skipped (empty window)\n', e); continue; end

    activeList = get_active_list(e);             % vector of CSC numbers
    activeMaskCSC = ismember(cscNums, activeList);  % 1 x nChan

    % Choose anchor
    switch alignMode
        case "midpoint"
            anchor = round((evS + evE)/2);
            s0 = max(1, anchor - HW); s1 = anchor + HW;
        otherwise % 'peak' per-channel
            s0 = evS; s1 = evE; % refine per-channel
    end

    % Read window per CSC
    if alignMode=="midpoint"
        winLen = s1 - s0 + 1;
        Y = nan(nChan, winLen, 'double');
        usedRows = false(1, nChan);
        for k = 1:nChan
            y = read_csc_samples(files(k), s0, s1, REC);
            if isempty(y), continue; end
            Y(k,:) = double(y) * scaleToMicroV;
            usedRows(k) = all(isfinite(Y(k,:)));
        end
        usedIdx = find(usedRows);
        if isempty(usedIdx)
            fprintf('Evt %d: no valid channels, skip.\n', e); continue;
        end
    else % per-channel peak
        rows = {}; usedIdx = [];
        for k = 1:nChan
            yRaw = read_csc_samples(files(k), evS, evE, REC);
            if isempty(yRaw), continue; end
            switch peakPolarity
                case 'pos', [~,kp] = max(yRaw);
                case 'neg', [~,kp] = min(yRaw);
                otherwise,  [~,kp] = max(abs(yRaw));
            end
            a = evS + kp - 1;
            s0k = max(1, a - HW); s1k = a + HW;
            yWin = read_csc_samples(files(k), s0k, s1k, REC);
            if numel(yWin) ~= (s1k - s0k + 1), continue; end
            rows{end+1} = double(yWin) * scaleToMicroV; %#ok<AGROW>
            usedIdx(end+1) = k; %#ok<AGROW>
        end
        if isempty(rows)
            fprintf('Evt %d: no valid channels (peak align), skip.\n', e); continue;
        end
        Y = cell2mat(rows(:));
        s0 = -HW; s1 = +HW; % relative only
    end

    % Time vectors and y-limits
    tRelSmps = -HW:HW;
    tRelMs   = (tRelSmps / sfx) * 1e3;
    maxAbs = max(abs(Y(:))); if ~isfinite(maxAbs)||maxAbs==0, maxAbs=1; end
    span = 1.05*maxAbs; yL = [-span, +span];

    % Figure
    nUsed = size(Y,1);
    perRowPx = 90; basePx = 200; maxPx = 5000;
    figH = min(maxPx, basePx + perRowPx*nUsed);
    f = figure('Color','w','Position',[60 60 900 figH],'Visible','off');
    tl = tiledlayout(f, nUsed, 1, 'Padding','compact', 'TileSpacing','compact');

    for r = 1:nUsed
        k = usedIdx(r);
        nexttile(tl); hold on; box on; grid on;

        isActive = activeMaskCSC(k);
        if isActive, lw=1.4; col=[0 0 0]; else, lw=0.7; col=[0.5 0.5 0.5]; end

        plot(tRelMs, Y(r,:), 'LineWidth', lw, 'Color', col);
        xline(0,'--k','LineWidth',0.8); yline(0,':','Color',[0.7 0.7 0.7]);
        ylim(yL);

        ttl = sprintf('row %d (CSC%d)%s', k, cscNums(k), tern(isActive,' *',''));
        title(ttl,'FontSize',8);

        ax=gca; ax.FontSize=8;
        if r<nUsed, ax.XTickLabel=[]; else, xlabel('ms'); end
        ylabel('\muV');
    end

    nActive = sum(activeMaskCSC);
    sgtitle(tl, sprintf('Evt %d  |  Active %d  |  Align: %s  |  Win ±%.1f ms  |  sfx=%g Hz', ...
        e, nActive, alignMode, 1e3*HW/sfx, sfx), ...
        'FontSize', 12, 'FontWeight', 'bold');

    outPng = fullfile(outDir, sprintf('Evt%03d_%dch_align-%s_HW%ds_rows-only_uV_fixedY.png', ...
                    e, nActive, alignMode, HW));
    exportgraphics(f, outPng, 'Resolution', 220);
    close(f);
    fprintf('Saved: %s\n', outPng);
end

fprintf('Done. Output dir: %s\n', outDir);
end

% ========== helpers ==========

function y = read_csc_samples(fileRec, s0, s1, REC)
% Return exact sample slice [s0..s1] (1-based) from CSC file via record-range read.
if s1 < s0, y = []; return; end
rec0 = floor((s0-1)/REC) + 1;
rec1 = floor((s1-1)/REC) + 1;
S = Nlx2MatCSC(fullfile(fileRec.folder, fileRec.name), [0 0 0 0 1], 0, 2, [rec0 rec1]);
if isempty(S), y = []; return; end
v = S(:)';                             % 512 x N -> row
off0 = s0 - ((rec0-1)*REC + 1);
off1 = s1 - ((rec0-1)*REC + 1);
i0 = max(0, off0); i1 = min(numel(v)-1, off1);
if i1 < i0, y = []; else, y = v(i0+1:i1+1); end
end

function s = tern(cond, a, b), if cond, s=a; else, s=b; end, end

function v = str2num_list(strCSV)
% Parse "2,4,6" or "2 4 6" -> [2 4 6]; trims spaces; empty -> []
strCSV = string(strCSV);
if strlength(strCSV)==0, v=[]; return; end
strCSV = regexprep(strCSV, '[\[\]\(\)]', '');
strCSV = strrep(strCSV,';',',');
parts = split(strtrim(strCSV), {',',' '});
parts = parts(parts~="");
v = str2double(parts); v = v(~isnan(v));
end
