function Batch_CSC_Tree_ToData(spreadsheetPath, baseRoot, varargin)
% Batch_CSC_Tree_ToData(spreadsheetPath, baseRoot, Name,Value...)
% - spreadsheetPath: xlsx/csv with columns:
%       col1 = mouse (e.g., 'm7' or 'M12something')
%       col2 = session number (e.g., 3 or '3')
%       (optional) columns for condition/group (ignored)
%       last (or a column named like 'bad*') = bad channels as text:
%           e.g., "2 or 4, 6 or 8, 12, 14"
% - baseRoot: folder that contains the three condition folders:
%       <baseRoot>\CTL, <baseRoot>\PTEN, <baseRoot>\PTEN_DKO
%
% It will:
%   1) Find each row’s .ncs leaf folder by searching under CTL/PTEN/PTEN_DKO
%   2) Run CSC2LL_uV_mex_disk(ncsLeaf, ...) to create LL-ready µV .mat
%   3) Copy the .mat to <baseRoot>\data\<relative_path_from_condition_root>
%   4) Add badch_user and badch_combined into the saved .mat
%
% Options (Name,Value):
%   'nTotalCh'   (default 64)        Total channel count
%   'evenOnly'   (default true)      Keep only even channels in converter
%   'keep'       (default [])        Explicit keep list (overrides evenOnly)
%   'storeClass' (default 'single')  'single' or 'double' in converter
%   'reqsPath'   (default ./reqsPath) Where Nlx2MatCSC MEX lives, if needed
%   'fallbackADBV' (default 0.00000006103515625) V/AD fallback
%   'outNameFmt' (default 'LL_input_M%02d_s%02d_uV.mat') output filename pattern
%
% Example:
%   Batch_CSC_Tree_ToData('sessions.xlsx','D:\proj\mice', ...
%       'nTotalCh',64,'evenOnly',true);

% -------- Parse args --------
ip = inputParser;
ip.addRequired('spreadsheetPath', @(s)ischar(s)||isstring(s));
ip.addRequired('baseRoot', @(s)ischar(s)||isstring(s));
ip.addParameter('nTotalCh', 64, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter('evenOnly', true, @(x)islogical(x)||ismember(x,[0,1]));
ip.addParameter('keep', [], @(v)isnumeric(v)&&isvector(v)&&all(v>=1));
ip.addParameter('storeClass', 'single', @(s)ischar(s)||isstring(s));
ip.addParameter('reqsPath', fullfile(fileparts(mfilename('fullpath')), 'reqsPath'), @(s)ischar(s)||isstring(s));
ip.addParameter('fallbackADBV', 0.00000006103515625, @(x)isfinite(x)&&x>0);
ip.addParameter('outNameFmt', 'LL_input_M%02d_s%02d_uV.mat', @(s)ischar(s)||isstring(s));
ip.parse(spreadsheetPath, baseRoot, varargin{:});

spreadsheetPath = char(ip.Results.spreadsheetPath);
baseRoot        = char(ip.Results.baseRoot);
nTotalCh        = ip.Results.nTotalCh;
evenOnly        = logical(ip.Results.evenOnly);
keepList        = ip.Results.keep;
storeClass      = char(ip.Results.storeClass);
reqsPath        = char(ip.Results.reqsPath);
fallbackADBV    = ip.Results.fallbackADBV;
outNameFmt      = char(ip.Results.outNameFmt);

assert(isfolder(baseRoot), "Base root not found: %s", baseRoot);

condNames = {'CTL','PTEN','PTEN_DKO'};
condDirs  = condNames(cellfun(@(c)isfolder(fullfile(baseRoot,c)), condNames));
if isempty(condDirs)
    error('None of CTL/PTEN/PTEN_DKO exist under baseRoot: %s', baseRoot);
end

% -------- Read spreadsheet --------
T = readtable(spreadsheetPath, 'TextType','string');
if width(T) < 2
    error('Spreadsheet must have at least two columns: mouse, session.');
end

% Identify bad-channel column
badCol = find(contains(lower(string(T.Properties.VariableNames)), "bad"), 1, 'first');
if isempty(badCol)
    badCol = width(T); % assume last column if not named
end

dataRoot = fullfile(baseRoot, 'data');
if ~isfolder(dataRoot), mkdir(dataRoot); end

fprintf('Found conditions: %s\n', strjoin(condDirs, ', '));
fprintf('Output mirror root: %s\n', dataRoot);

% -------- Iterate rows --------
for r = 1:height(T)
    mouseRaw = T{r,1};
    sessRaw  = T{r,2};

    mouseNum = extractFirstInt(mouseRaw);
    sessNum  = extractFirstInt(sessRaw);

    if isnan(mouseNum) || isnan(sessNum)
        warning('Row %d skipped (no mouse/session integer parsed).', r);
        continue;
    end

    badList = parseBadList(T{r,badCol});
    badList = badList(badList>=1 & badList<=nTotalCh);
    badList = unique(badList(:)');

    % --- locate mouse folder (search each condition) ---
    found = false; chosen = struct;
    for ci = 1:numel(condDirs)
        condName = condDirs{ci};
        condPath = fullfile(baseRoot, condName);

        mFolder = findMouseFolder(condPath, mouseNum);
        if isempty(mFolder), continue; end

        % --- locate session leaf with .ncs ---
        [sessLeaf, mouseFolderName, relUnderCond] = findSessionLeafWithNcs(mFolder, mouseNum, sessNum, condPath);
        if isempty(sessLeaf), continue; end

        chosen.condName        = condName;
        chosen.condPath        = condPath;
        chosen.mouseFolderPath = mFolder;
        chosen.mouseFolderName = mouseFolderName;
        chosen.sessLeaf        = sessLeaf;
        chosen.relUnderCond    = relUnderCond; % relative path from condition root to leaf
        found = true;
        break;
    end

    if ~found
        warning('Row %d (M%d S%d): no .ncs leaf found under any condition.', r, mouseNum, sessNum);
        continue;
    end

    % --- Run converter on sessLeaf ---
    outName = sprintf(outNameFmt, mouseNum, sessNum);
    try
        CSC2LL_uV_mex_disk(chosen.sessLeaf, ...
            'nTotalCh', nTotalCh, ...
            'evenOnly', evenOnly, ...
            'keep', keepList, ...
            'storeClass', storeClass, ...
            'outName', outName, ...
            'fallbackADBV', fallbackADBV, ...
            'reqsPath', reqsPath);
    catch ME
        warning('Converter failed for %s (row %d): %s', chosen.sessLeaf, r, ME.message);
        continue;
    end

    srcMat  = fullfile(chosen.sessLeaf, outName);
    if ~isfile(srcMat)
        warning('Expected output not found: %s', srcMat);
        continue;
    end

    % --- Mirror path in data/ and copy ---
    destDir = fullfile(dataRoot, chosen.relUnderCond);
    if ~isfolder(destDir), mkdir(destDir); end
    destMat = fullfile(destDir, outName);

    try
        copyfile(srcMat, destMat);
    catch ME
        warning('Copy failed to %s: %s', destMat, ME.message);
        continue;
    end

    % --- Inject user bad channels & metadata into the mirrored copy ---
    try
        mf = matfile(destMat, 'Writable', true);

        % Build badch_user in original indexing space (1..nTotalCh)
        badch_user = false(1, nTotalCh);
        badch_user(badList) = true;

        % Combine with existing 'badch' if present
        try
            existing_badch = mf.badch;
            if numel(existing_badch) ~= nTotalCh
                % if dimensions disagree, best-effort pad/trim
                tmp = false(1, nTotalCh);
                ncopy = min(numel(existing_badch), nTotalCh);
                tmp(1:ncopy) = existing_badch(1:ncopy);
                existing_badch = tmp;
            end
        catch
            existing_badch = false(1, nTotalCh);
        end

        badch_combined = existing_badch | badch_user;

        mf.badch_user     = badch_user;
        mf.badch_combined = badch_combined;

        % Update meta with row info
        try
            mmeta = mf.meta; % read-then-write pattern for struct
        catch
            mmeta = struct;
        end
        mmeta.mouseID          = mouseNum;
        mmeta.sessionID        = sessNum;
        mmeta.condition        = chosen.condName;
        mmeta.source_ncs_path  = chosen.sessLeaf;
        mmeta.spreadsheet_row  = r;
        mmeta.badch_user_list  = badList;
        mmeta.mirrored_relpath = chosen.relUnderCond;
        mf.meta = mmeta;

        fprintf('Row %d: M%d S%d → %s\n', r, mouseNum, sessNum, destMat);
    catch ME
        warning('Failed to annotate %s: %s', destMat, ME.message);
    end
end

fprintf('\nAll done. Mirrored outputs under: %s\n', dataRoot);
end

% ---------- helpers ----------

function n = extractFirstInt(x)
    if ismissing(x) || (ischar(x) && isempty(x)), n = NaN; return; end
    s = string(x);
    tok = regexp(s, '(\d+)', 'tokens', 'once');
    if isempty(tok), n = NaN; else, n = str2double(tok{1}); end
end

function v = parseBadList(x)
    % Pull every integer from a messy text like "2 or 4, 6 or 8, 12, 14"
    if ismissing(x) || (ischar(x) && isempty(x)), v = []; return; end
    s = string(x);
    toks = regexp(s, '(\d+)', 'tokens');
    v = [];
    for k = 1:numel(toks)
        if ~isempty(toks{k}), v = [v, str2double([toks{k}{:}])]; end %#ok<AGROW>
    end
    v = unique(v);
end

function mFolder = findMouseFolder(condPath, mouseNum)
    % Find a folder under condPath whose name starts with 'M<mouseNum>' (case-insensitive),
    % allowing extra suffix text (e.g., "M12_ptenDoubleBlind")
    mFolder = '';
    D = dir(fullfile(condPath, 'M*'));
    D = D([D.isdir]);
    pat = sprintf('^M0*%d\\b', mouseNum);
    for i = 1:numel(D)
        if ~isempty(regexpi(D(i).name, pat, 'once'))
            mFolder = fullfile(condPath, D(i).name);
            return;
        end
    end
end

function [sessLeaf, mouseFolderName, relUnderCond] = findSessionLeafWithNcs(mFolder, mouseNum, sessNum, condPath)
    % Find a session directory under mFolder matching '*s<sessNum>*' (case-insensitive),
    % then find the leaf directory that actually contains the .ncs files.
    sessLeaf = '';
    mouseFolderName = string(split(mFolder, filesep)); mouseFolderName = mouseFolderName(end);
    relUnderCond = '';
    % Search for any directory that contains 's<sessNum>' in its name
    tag = sprintf('s%d', sessNum);
    C = dir(fullfile(mFolder, '**')); % recursive
    C = C([C.isdir]);
    % Prefer folders that include both 'm<mouseNum>' and 's<sessNum>' somewhere in the name chain
    candidates = {};
    for i = 1:numel(C)
        nm = C(i).name;
        if nm=="." || nm=="..", continue; end
        if ~isempty(regexpi(nm, tag, 'once'))
            candidates{end+1} = fullfile(C(i).folder, nm); %#ok<AGROW>
        end
    end
    % If none found by tag, accept mouse root as candidate (we'll still search for .ncs under it)
    if isempty(candidates)
        candidates = {mFolder};
    end

    % For each candidate, try to locate the true .ncs leaf (folder that holds CSC#.ncs)
    for i = 1:numel(candidates)
        leaf = findNcsLeaf(candidates{i});
        if ~isempty(leaf)
            sessLeaf = leaf;
            % Make relative path under condition root (mirror everything after condPath\)
            relUnderCond = erase(sessLeaf, [condPath filesep]);
            return;
        end
    end
end

function leaf = findNcsLeaf(rootDir)
    % Return the directory that actually contains any CSC*.ncs files.
    leaf = '';
    F = dir(fullfile(rootDir, '**', 'CSC*.ncs')); % recursive file search
    if isempty(F), return; end
    % Take the folder of the first hit; you can improve selection if needed
    leaf = F(1).folder;
end
