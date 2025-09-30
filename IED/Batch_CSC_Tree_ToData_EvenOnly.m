function Batch_CSC_Tree_ToData_EvenOnly(spreadsheetPath, baseRoot, varargin)
% Batch_CSC_Tree_ToData_EvenOnly(spreadsheetPath, baseRoot, Name,Value...)
% Reads spreadsheet (mouse, session, bad channels), finds .ncs leaves under
% CTL/PTEN/PTEN_DKO, chooses ONLY EVEN channels; if an even channel is bad/missing,
% substitutes a nearby good ODD channel. Runs CSC2LL_uV_mex_disk and mirrors to /data.
%
% REQUIRED:
%   spreadsheetPath : .xlsx/.csv with at least 2 cols: [mouse, session, ... bad?]
%   baseRoot        : folder containing CTL, PTEN, PTEN_DKO
%
% OPTIONS:
%   'nTotalCh'        (64)
%   'storeClass'      ('single')
%   'reqsPath'        (./reqsPath)
%   'fallbackADBV'    (0.00000006103515625)   % V/AD
%   'outNameFmt'      ('LL_input_M%02d_s%02d_uV.mat')
%   'debugMode'       (false)  % if true: only 2 rows, only 2 channels per row
%   'debugMaxRows'    (2)
%   'debugMaxChannels'(2)
%
% DEPENDS ON: CSC2LL_uV_mex_disk (from earlier message) on MATLAB path.

% ---------- Parse args ----------
ip = inputParser;
ip.addRequired('spreadsheetPath', @(s)ischar(s)||isstring(s));
ip.addRequired('baseRoot', @(s)ischar(s)||isstring(s));
ip.addParameter('nTotalCh', 64, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter('storeClass', 'single', @(s)ischar(s)||isstring(s));
ip.addParameter('reqsPath', fullfile(fileparts(mfilename('fullpath')), 'reqsPath'), @(s)ischar(s)||isstring(s));
ip.addParameter('fallbackADBV', 0.00000006103515625, @(x)isfinite(x)&&x>0);
ip.addParameter('outNameFmt', 'LL_input_M%02d_s%02d_uV.mat', @(s)ischar(s)||isstring(s));
ip.addParameter('debugMode', false, @(x)islogical(x)||ismember(x,[0,1]));
ip.addParameter('debugMaxRows', 2, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter('debugMaxChannels', 2, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.parse(spreadsheetPath, baseRoot, varargin{:});

spreadsheetPath  = char(ip.Results.spreadsheetPath);
baseRoot         = char(ip.Results.baseRoot);
nTotalCh         = ip.Results.nTotalCh;
storeClass       = char(ip.Results.storeClass);
reqsPath         = char(ip.Results.reqsPath);
fallbackADBV     = ip.Results.fallbackADBV;
outNameFmt       = char(ip.Results.outNameFmt);
debugMode        = logical(ip.Results.debugMode);
debugMaxRows     = ip.Results.debugMaxRows;
debugMaxChannels = ip.Results.debugMaxChannels;

assert(isfolder(baseRoot), "Base root not found: %s", baseRoot);
dataRoot = fullfile(baseRoot,'data'); if ~isfolder(dataRoot), mkdir(dataRoot); end

condNames = {'CTL','PTEN','PTEN_DKO'};
condDirs  = condNames(cellfun(@(c)isfolder(fullfile(baseRoot,c)),condNames));
if isempty(condDirs)
    error('None of CTL/PTEN/PTEN_DKO exist under baseRoot: %s', baseRoot);
end
fprintf('Conditions found: %s\n', strjoin(condDirs, ', '));
fprintf('Mirroring to: %s\n', dataRoot);

% ---------- Read spreadsheet ----------
T = readtable(spreadsheetPath, 'TextType','string');
if width(T)<2, error('Spreadsheet needs at least [mouse, session] columns.'); end
badCol = find(contains(lower(string(T.Properties.VariableNames)),"bad"),1,'first');
if isempty(badCol), badCol = width(T); end  % assume last col holds bad channels if not named

rowIndices = 1:height(T);
if debugMode
    rowIndices = rowIndices(1:min(debugMaxRows, numel(rowIndices)));
    fprintf('[DEBUG] Limiting to %d rows, %d channels per row\n', numel(rowIndices), debugMaxChannels);
end

% ---------- Iterate rows ----------
for idx = rowIndices
    mouseNum = extractFirstInt(T{idx,1});
    sessNum  = extractFirstInt(T{idx,2});
    if isnan(mouseNum) || isnan(sessNum)
        warning('Row %d skipped (couldn''t parse mouse/session).', idx);
        continue;
    end
    badList = parseBadList(T{idx,badCol});
    badList = unique(badList(badList>=1 & badList<=nTotalCh));

    % Locate session .ncs leaf by searching all conditions
    found = false; chosen = struct;
    for ci = 1:numel(condDirs)
        condName = condDirs{ci};
        condPath = fullfile(baseRoot, condName);
        mFolder  = findMouseFolder(condPath, mouseNum);
        if isempty(mFolder), continue; end
        [sessLeaf, ~, relUnderCond] = findSessionLeafWithNcs(mFolder, mouseNum, sessNum, condPath);
        if isempty(sessLeaf), continue; end
        chosen.condName     = condName;
        chosen.condPath     = condPath;
        chosen.sessLeaf     = sessLeaf;
        chosen.relUnderCond = relUnderCond;
        found = true; break;
    end
    if ~found
        warning('Row %d (M%d S%d): no .ncs folder found under any condition.', idx, mouseNum, sessNum);
        continue;
    end

    % Compute keep-list: even-only w/ odd fallback based on presence & badList
    [keepComputed, mappingPairs, presentVec] = chooseEvenWithOddFallback(chosen.sessLeaf, nTotalCh, badList);

    if isempty(keepComputed)
        warning('Row %d (M%d S%d): no usable channels after substitution.', idx, mouseNum, sessNum);
        continue;
    end

    if debugMode
        keepComputed = keepComputed(1:min(debugMaxChannels, numel(keepComputed)));
        mappingPairs = mappingPairs(ismember(mappingPairs(:,2), keepComputed),:);
        fprintf('[DEBUG] Using channels: %s\n', mat2str(keepComputed));
    else
        fprintf('Using channels: %s\n', prettyList(keepComputed, 40));
    end

    % Run converter with explicit keep-list (override evenOnly logic)
    outName = sprintf(outNameFmt, mouseNum, sessNum);
    try
        CSC2LL_uV_mex_disk(chosen.sessLeaf, ...
            'nTotalCh', nTotalCh, ...
            'evenOnly', false, ...         % we are supplying 'keep'
            'keep', keepComputed, ...
            'storeClass', storeClass, ...
            'outName', outName, ...
            'fallbackADBV', fallbackADBV, ...
            'reqsPath', reqsPath);
    catch ME
        warning('Converter failed for %s (row %d): %s', chosen.sessLeaf, idx, ME.message);
        continue;
    end

    % Mirror output to /data tree
    srcMat  = fullfile(chosen.sessLeaf, outName);
    if ~isfile(srcMat), warning('Expected output missing: %s', srcMat); continue; end
    destDir = fullfile(dataRoot, chosen.relUnderCond); if ~isfolder(destDir), mkdir(destDir); end
    destMat = fullfile(destDir, outName);
    try, copyfile(srcMat, destMat); catch ME, warning('Copy failed: %s', ME.message); continue; end

    % Inject badch_user/combined and selection metadata
    try
        mf = matfile(destMat,'Writable',true);
        badch_user = false(1, nTotalCh); badch_user(badList) = true;

        try, existing_badch = mf.badch;
        catch, existing_badch = false(1, nTotalCh); end
        if numel(existing_badch)~=nTotalCh
            tmp = false(1, nTotalCh);
            ncopy = min(numel(existing_badch), nTotalCh);
            tmp(1:ncopy) = existing_badch(1:ncopy);
            existing_badch = tmp;
        end
        badch_combined = existing_badch | badch_user;

        mf.badch_user     = badch_user;
        mf.badch_combined = badch_combined;

        try, mmeta = mf.meta; catch, mmeta = struct; end
        mmeta.mouseID                 = mouseNum;
        mmeta.sessionID               = sessNum;
        mmeta.condition               = chosen.condName;
        mmeta.source_ncs_path         = chosen.sessLeaf;
        mmeta.spreadsheet_row         = idx;
        mmeta.badch_user_list         = badList;
        mmeta.selection_policy        = 'even_preferred_with_odd_substitution';
        mmeta.target_even_list        = 2:2:nTotalCh;
        mmeta.files_present           = find(presentVec);
        mmeta.chosen_keep_list        = keepComputed;
        mmeta.even_to_used_pairs      = mappingPairs;   % [target_even, used_channel]
        mf.meta = mmeta;

        fprintf('Row %d: M%d S%d → %s\n', idx, mouseNum, sessNum, destMat);
    catch ME
        warning('Annotate failed for %s: %s', destMat, ME.message);
    end
end

fprintf('\nAll done. Outputs under: %s\n', dataRoot);
end

% ======== helpers ========

function n = extractFirstInt(x)
    if ismissing(x) || (ischar(x) && isempty(x)), n = NaN; return; end
    s = string(x); tok = regexp(s, '(\d+)', 'tokens', 'once');
    n = iff(isempty(tok), NaN, str2double(tok{1}));
end

function v = parseBadList(x)
    if ismissing(x) || (ischar(x) && isempty(x)), v = []; return; end
    s = string(x); toks = regexp(s, '(\d+)', 'tokens');
    v = []; for k=1:numel(toks), if ~isempty(toks{k}), v=[v, str2double([toks{k}{:}])]; end, end %#ok<AGROW>
    v = unique(v);
end

function out = iff(cond,a,b), if cond, out=a; else, out=b; end, end

function mFolder = findMouseFolder(condPath, mouseNum)
    mFolder = '';
    D = dir(fullfile(condPath, 'M*')); D = D([D.isdir]);
    pat = sprintf('^M0*%d\\b', mouseNum);
    for i = 1:numel(D)
        if ~isempty(regexpi(D(i).name, pat, 'once'))
            mFolder = fullfile(condPath, D(i).name); return;
        end
    end
end

function [sessLeaf, mouseFolderName, relUnderCond] = findSessionLeafWithNcs(mFolder, mouseNum, sessNum, condPath)
    sessLeaf = ''; mouseFolderName = string(split(mFolder, filesep)); mouseFolderName = mouseFolderName(end);
    relUnderCond = '';
    tag = sprintf('s%d', sessNum);
    C = dir(fullfile(mFolder, '**')); C = C([C.isdir]);
    candidates = {};
    for i = 1:numel(C)
        nm = C(i).name; if nm=="."||nm=="..", continue; end
        if ~isempty(regexpi(nm, tag, 'once')), candidates{end+1} = fullfile(C(i).folder,nm); end %#ok<AGROW>
    end
    if isempty(candidates), candidates = {mFolder}; end
    for i = 1:numel(candidates)
        leaf = findNcsLeaf(candidates{i});
        if ~isempty(leaf)
            sessLeaf = leaf;
            relUnderCond = erase(sessLeaf, [condPath filesep]);
            return;
        end
    end
end

function leaf = findNcsLeaf(rootDir)
    leaf = '';
    F = dir(fullfile(rootDir, '**', 'CSC*.ncs'));
    if isempty(F), return; end
    leaf = F(1).folder;
end

function [keepList, mappingPairs, present] = chooseEvenWithOddFallback(sessLeaf, nTotalCh, bad_user_list)
    % Build presence vector
    present = false(1, nTotalCh);
    F = dir(fullfile(sessLeaf, 'CSC*.ncs'));
    for i=1:numel(F)
        tok = regexp(F(i).name, '^CSC(\d+)\.ncs$', 'tokens', 'once');
        if ~isempty(tok)
            k = str2double(tok{1}); if k>=1 && k<=nTotalCh, present(k)=true; end
        end
    end
    bad_user = false(1,nTotalCh); bad_user(bad_user_list) = true;
    good = present & ~bad_user;

    targetEvens = 2:2:nTotalCh;
    used = false(1, nTotalCh);
    keep = []; pairs = [];

    for e = targetEvens
        if e<=nTotalCh && good(e) && ~used(e)
            keep(end+1) = e; used(e) = true; pairs(end+1,:) = [e e]; %#ok<AGROW>
            continue;
        end
        % find nearest odd: e-1, e+1, then ±3, ±5, ...
        maxDelta = max([e-1, nTotalCh-e]); % safe bound
        chosen = NaN;
        for d = 1:2:max(1,2*ceil(maxDelta))  % odd deltas
            candList = unique([e-d, e+d]);
            for c = candList
                if c>=1 && c<=nTotalCh && mod(c,2)==1 && good(c) && ~used(c)
                    chosen = c; break;
                end
            end
            if ~isnan(chosen), break; end
        end
        if ~isnan(chosen)
            keep(end+1) = chosen; used(chosen)=true; pairs(end+1,:) = [e chosen]; %#ok<AGROW>
        else
            % no substitute found; skip this even
            pairs(end+1,:) = [e 0]; %#ok<AGROW>
        end
    end

    keepList     = unique(keep, 'stable');
    mappingPairs = pairs;
end

function s = prettyList(v, maxChars)
    s = mat2str(v);
    if nargin<2, maxChars=60; end
    if strlength(s) > maxChars
        s = extractBefore(s, maxChars) + " …]";
    end
end
