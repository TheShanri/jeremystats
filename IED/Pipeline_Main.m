function [grpTbl, chTbl] = statsFrom_EventStacks(out)
% Normalizes EventStacks_ampWidth_Avg_Pipeline outputs into:
%   grpTbl         : one row per group (SCALARS ONLY)
%   chTbl          : one row per channel per group

moduleName = "EventStacks_ampWidth_Avg";

% ---- fixed-type empty tables (so vertcat has consistent types) ----
grpTbl = table( ...
    strings(0,1), ... % Module
    strings(0,1), ... % Group
    zeros(0,1), ...   % NEvents
    zeros(0,1), ...   % NChannels
    zeros(0,1), ...   % AmpMean_uV
    zeros(0,1), ...   % AmpSD_uV
    zeros(0,1), ...   % HW_Mean_ms
    zeros(0,1), ...   % HW_SD_ms
    'VariableNames', {'Module','Group','NEvents','NChannels','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});

chTbl = table( ...
    strings(0,1), ... % Module
    strings(0,1), ... % Group
    zeros(0,1), ...   % ChannelIndex
    zeros(0,1), ...   % CSC
    zeros(0,1), ...   % NUsed
    zeros(0,1), ...   % AmpMean_uV
    zeros(0,1), ...   % AmpSD_uV
    zeros(0,1), ...   % HW_Mean_ms
    zeros(0,1), ...   % HW_SD_ms
    'VariableNames', {'Module','Group','ChannelIndex','CSC','NUsed','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});

% Channel list & CSC list (CSC may be missing)
nCh = numel(out.channelList);
if isfield(out,'kept_channels') && ~isempty(out.kept_channels)
    cscVec = out.kept_channels(:);
    if numel(cscVec) < max(out.channelList)
        cscVec(end+1:max(out.channelList)) = NaN; %#ok<AGROW>
    end
else
    cscVec = nan(max(out.channelList),1);
end

% ---- iterate groups ----
for g = 1:numel(out.groups)
    G = out.groups(g);
    groupTag = string(G.tag);

    % ---------- SCALARIFY group-level metrics ----------
    nEvents = scalarify(getfieldsafe(G,'nEventsUsed'), 0); %#ok<GFLD>
    if nEvents<=0
        % Still emit a row of NaNs so downstream stays consistent
        rowG = table( ...
            moduleName, groupTag, ...
            double(nEvents), double(nCh), ...
            NaN, NaN, NaN, NaN, ...
            'VariableNames', {'Module','Group','NEvents','NChannels','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});
        grpTbl = [grpTbl; rowG];
        % And skip channel rows for this group
        continue;
    end

    ampMean_scalar = scalarMean(getfieldsafe(G,'ampMean'));   % vector -> scalar
    ampSD_scalar   = scalarMean(getfieldsafe(G,'ampSD'));
    hwMean_scalar  = scalarMean(getfieldsafe(G,'hwMean'));
    hwSD_scalar    = scalarMean(getfieldsafe(G,'hwSD'));

    rowG = table( ...
        moduleName, groupTag, ...
        double(nEvents), double(nCh), ...
        double(ampMean_scalar), double(ampSD_scalar), ...
        double(hwMean_scalar),  double(hwSD_scalar), ...
        'VariableNames', {'Module','Group','NEvents','NChannels','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});

    grpTbl = [grpTbl; rowG];

    % ---------- Channel-level tall rows ----------
    % fallbacks to NaN with correct shapes if fields are missing
    nUsed  = asVec(getfieldsafe(G,'n'),      nCh);
    aMean  = asVec(getfieldsafe(G,'ampMean'),nCh);
    aSD    = asVec(getfieldsafe(G,'ampSD'),  nCh);
    hMean  = asVec(getfieldsafe(G,'hwMean'), nCh);
    hSD    = asVec(getfieldsafe(G,'hwSD'),   nCh);

    for k = 1:nCh
        ch = out.channelList(k);
        csc = getIdx(cscVec, ch);

        rowC = table( ...
            moduleName, groupTag, ...
            double(ch), double(csc), ...
            double(nUsed(k)), ...
            double(aMean(k)), double(aSD(k)), ...
            double(hMean(k)), double(hSD(k)), ...
            'VariableNames', {'Module','Group','ChannelIndex','CSC','NUsed','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});

        chTbl = [chTbl; rowC];
    end
end
end

% =================== tiny helpers ===================

function x = getfieldsafe(S, fname, defaultVal)
if nargin<3, defaultVal = []; end
if isstruct(S) && isfield(S,fname)
    x = S.(fname);
else
    x = defaultVal;
end
end

function s = scalarify(x, nanIfEmpty)
if nargin<2, nanIfEmpty = NaN; end
% turn anything into a scalar double
if isempty(x)
    s = nanIfEmpty; return;
end
if isstruct(x) || istable(x) || iscell(x)
    s = nanIfEmpty; return;
end
x = double(x);
if ~isvector(x)
    s = mean(x(:), 'omitnan');  % squeeze matrices to scalar
else
    if numel(x)==1
        s = x;
    else
        s = mean(x, 'omitnan'); % vector -> scalar mean
    end
end
if isempty(s), s = nanIfEmpty; end
end

function m = scalarMean(v)
% vector/array -> scalar mean (NaN-safe); empty -> NaN
if isempty(v)
    m = NaN;
else
    m = mean(double(v(:)), 'omitnan');
end
end

function v = asVec(x, nCh)
% ensure a length-nCh column vector of doubles (NaN-filled if needed)
x = double(x);
if isempty(x)
    v = nan(nCh,1);
else
    x = x(:);
    if numel(x) < nCh
        v = nan(nCh,1);
        v(1:numel(x)) = x;
    else
        v = x(1:nCh);
    end
end
end

function v = getIdx(vec, idx)
% safe indexing returning NaN if out-of-range
if idx>=1 && idx<=numel(vec) && ~isempty(vec(idx))
    v = vec(idx);
else
    v = NaN;
end
end
