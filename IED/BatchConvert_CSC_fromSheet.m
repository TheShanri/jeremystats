function BatchConvert_CSC_fromSheet(sheetPath, baseRoot, outRoot, varargin)
% BatchConvert_CSC_fromSheet
% Read a spreadsheet of (mouse_id, session, group, bad channel, …),
% locate each recording under baseRoot, convert CSC#.ncs → LL-ready µV .mat,
% and save under outRoot mirroring the source folder structure.
%
% Usage:
%   BatchConvert_CSC_fromSheet('samples.xlsx', 'D:\DATA', 'E:\LL_ready_out')
%   BatchConvert_CSC_fromSheet('samples.csv',  'D:\DATA', 'E:\LL_ready_out', ...
%       'nTotalCh',64,'storeClass','single','reqsPath','.\reqsPath','dryRun',false)
%
% Required inputs:
%   sheetPath : Excel/CSV with columns including mouse_id, session, (group optional), bad channel
%   baseRoot  : top-level data folder that contains group folders, mouse folders, etc.
%   outRoot   : destination top-level folder (the relative path from baseRoot is mirrored here)
%
% Name-Value options:
%   'nTotalCh'     (default 64)
%   'storeClass'   (default 'single')  % 'single'|'double'
%   'reqsPath'     (default ./reqsPath)  % folder containing Nlx2MatCSC MEX (if not on path)
%   'fallbackADBV' (default 0.00000006103515625) % V/AD if header missing ADBitVolts
%   'dryRun'       (default false)  % if true, only lists what it would do (no conversion)
%   'verbose'      (default true)

% ---------------- Parse args ----------------
ip = inputParser;
ip.addRequired('sheetPath', @(s)ischar(s)||isstring(s));
ip.addRequired('baseRoot',  @(s)ischar(s)||isstring(s));
ip.addRequired('outRoot',   @(s)ischar(s)||isstring(s));
ip.addParameter('nTotalCh', 64, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
ip.addParameter('storeClass','single', @(s)ischar(s)||isstring(s));
ip.addParameter('reqsPath', fullfile(fileparts(mfilename('fullpath')),'reqsPath'), @(s)ischar(s)||isstring(s));
ip.addParameter('fallbackADBV', 0.00000006103515625, @(x)isfinite(x)&&x>0);
ip.addParameter('dryRun', false, @(x)islogical(x)||ismember(x,[0 1]));
ip.addParameter('verbose', true, @(x)islogical(x)||ismember(x,[0 1]));
ip.parse(sheetPath, baseRoot, outRoot, varargin{:});
opts = ip.Results;
baseRoot = char(baseRoot);
outRoot  = char(outRoot);

if ~isfolder(baseRoot), error('Base folder not found: %s', baseRoot); end
if ~isfolder(outRoot),  mkdir(outRoot); end

% --------------- Load spreadsheet ---------------
T = readtable(sheetPath);
% Normalize column names
cn = lower(regexprep(string(T.Properties.VariableNames), '\s+', ''));
T.Properties.VariableNames = cellstr(cn);

% Expected columns (tolerant names)
col_mouse = find(ismember(cn, ["mouse_id","mouse","mouseid","animal","subject"]), 1);
col_sess  = find(ismember(cn, ["session","sess"]), 1);
col_group = find(ismember(cn, ["group","grp","condition"]), 1); %#ok<NASGU> % not strictly required
col_bad   = find(ismember(cn, ["badchannel","badchannels","bad_channel","bad_channels","bad"]), 1);

if isempty(col_mouse) || isempty(col_sess)
    error('Spreadsheet must have at least "mouse_id" and "session" columns.');
end

% --------------- Find top-level group folders ---------------
grpDirs = dir(baseRoot);
grpDirs = grpDirs([grpDirs.isdir] & ~startsWith({grpDirs.name}, '.'));
grpPaths = fullfile(baseRoot, {grpDirs.name});

% --------------- Process each row ---------------
for r = 1:height(T)
    mouse_id_raw = string(T{r, col_mouse});
    sess_raw     = T{r, col_sess};
    bad_raw      = "";
    if ~isempty(col_bad), bad_raw = string(T{r, col_bad}); end

    % Extract mouse digits from mouse_id like "m1", "M10", etc.
    mdig = regexp(lower(strtrim(mouse_id_raw)), 'm\s*0*(\d+)', 'tokens', 'once');
    if isempty(mdig)
        warning('Row %d: could not parse mouse_id "%s" → skipping.', r, mouse_id_raw);
        continue;
    end
    mouseNum = str2double(mdig{1});

    % Session number (accept numeric or s# in text)
    if ischar(sess_raw) || isstring(sess_raw)
        sdig = regexp(lower(string(sess_raw)), 's\s*0*(\d+)', 'tokens', 'once');
        if isempty(sdig)
            % maybe just a number in text
            sdig = regexp(lower(string(sess_raw)), '0*(\d+)', 'tokens', 'once');
        end
        if isempty(sdig), warning('Row %d: bad session "%s" → skipping.', r, string(sess_raw)); continue; end
        sessNum = str2double(sdig{1});
    else
        sessNum = double(sess_raw);
    end

    % Bad channel list → numeric vector
    badList = [];
    if strlength(strtrim(bad_raw))>0
        toks = regexp(char(bad_raw), '\d+', 'match');
        badList = unique(str2double(toks));
    end

    if opts.verbose
        fprintf('\n[%3d/%3d] mouse m%d | session s%d | badList=%s\n', ...
            r, height(T), mouseNum, sessNum, mat2str(badList));
    end

    % ---------- Locate mouse folder under ANY group folder ----------
    mousePat = sprintf('m0*%d(?!\\d)', mouseNum); % ensure mX not mX0...
    mouseHits = {};
    for g = 1:numel(grpPaths)
        hits = findDirsRegex(grpPaths{g}, mousePat);
        mouseHits = [mouseHits, hits]; %#ok<AGROW>
    end
    if isempty(mouseHits)
        warning('Row %d: mouse m%d not found under any group folder.', r, mouseNum);
        continue;
    end
    % Prefer the shallowest path (closest to group root)
    depths = cellfun(@(p) count(p, filesep), mouseHits);
    [~, ix] = sort(depths, 'ascend');
    mouseHits = mouseHits(ix);

    % ---------- Locate session folder within chosen mouse folder ----------
    sessPat = sprintf('s0*%d(?!\\d)', sessNum);
    sessHits = findDirsRegex(mouseHits{1}, sessPat);
    if isempty(sessHits)
        warning('Row %d: session s%d not found under mouse folder: %s', r, sessNum, mouseHits{1});
        continue;
    end

    % ---------- Find recording leaf dirs containing CSC*.ncs ----------
    recDirs = {};
    for s = 1:numel(sessHits)
        cscFiles = dir(fullfile(sessHits{s}, '**', 'CSC*.ncs'));
        if ~isempty(cscFiles)
            recDirs = [recDirs, unique(cellfun(@(p) fileparts(p), ...
                fullfile({cscFiles.folder}, {cscFiles.name}), 'UniformOutput', false))]; %#ok<AGROW>
        end
    end
    recDirs = unique(recDirs);
    if isempty(recDirs)
        warning('Row %d: no CSC*.ncs under session path(s).', r);
        continue;
    end

    % ---------- Build keep set: even channels; replace bad evens with (e+1) ----------
    keep = 2:2:opts.nTotalCh;
    badEven = intersect(keep, badList);
    replacements = [];
    for be = badEven
        rep = be+1;
        if rep > opts.nTotalCh, rep = be-1; end % fallback if even is the last channel
        % Remove the bad even, add replacement odd (if in range)
        keep(keep==be) = [];
        if rep>=1 && rep<=opts.nTotalCh
            replacements(end+1,:) = [be, rep]; %#ok<AGROW>
            keep = unique([keep, rep]); %#ok<AGROW>
        end
    end
    if opts.verbose
        if ~isempty(replacements)
            fprintf('  Replacements (even→odd): %s\n', mat2str(replacements));
        end
        fprintf('  Final keep (%d ch): first few %s ...\n', numel(keep), mat2str(keep(1:min(12,end))));
    end

    % ---------- Convert each recDir and mirror path to outRoot ----------
    for d = 1:numel(recDirs)
        srcDir = recDirs{d};
        relPath = erase(srcDir, append(filesep)); % normalize
        % make relative path from baseRoot
        if startsWith(srcDir, baseRoot)
            relPath = srcDir(length(baseRoot)+2:end); % +2 for trailing filesep
        else
            % fallback: compute relative via split
            relPath = srcDir; % best-effort if baseRoot isn't a prefix
        end
        dstDir = fullfile(outRoot, relPath);
        if opts.dryRun
            fprintf('  [dry-run] Would convert: %s\n              → %s\n', srcDir, dstDir);
            continue;
        end
        mkdir(dstDir);

        try
            convertFolderToLL_uV(srcDir, dstDir, keep, opts);
        catch ME
            warning('  Conversion failed for %s: %s', srcDir, ME.message);
        end
    end
end

fprintf('\nAll rows processed.\n');

end % === main ===



% ===== Helper: find subdirectories whose NAME matches a regex (case-insensitive) =====
function hits = findDirsRegex(rootDir, nameRegex)
    % Search breadth-first for dirs whose final path component matches the regex.
    % We only match the folder name, not entire path.
    hits = {};
    queue = {rootDir};
    while ~isempty(queue)
        d = queue{1}; queue(1) = [];
        dd = dir(d);
        dd = dd([dd.isdir] & ~startsWith({dd.name}, '.'));
        for k = 1:numel(dd)
            sub = fullfile(d, dd(k).name);
            if ~isempty(regexpi(dd(k).name, ['(^|[\W_])', nameRegex, '($|[\W_])']))
                hits{end+1} = sub; %#ok<AGROW>
            end
            queue{end+1} = sub; %#ok<AGROW>
        end
    end
    hits = unique(hits);
end



% ===== Conversion engine: CSC*.ncs → LL-ready µV .mat at dstDir =====
function convertFolderToLL_uV(basePath, outDir, keep, opts)
    % Ensure Nlx2MatCSC MEX is accessible
    if isfolder(opts.reqsPath), addpath(opts.reqsPath); end
    rehash toolboxcache; clear mex;
    nlxPaths = which('-all','Nlx2MatCSC');
    if isempty(nlxPaths)
        error('Nlx2MatCSC not found. Put Nlx2MatCSC.%s in reqsPath or add its folder.', mexext);
    end
    if ~any(endsWith(string(nlxPaths), ['.',mexext], 'IgnoreCase',true))
        error('Only Nlx2MatCSC.m visible. Ensure Nlx2MatCSC.%s (MEX) is earlier on the path.', mexext);
    end

    % Determine out file name based on leaf folder
    [~, tail] = fileparts(basePath);
    outName = sprintf('LL_input_%s_uV.mat', tail);
    outFull = fullfile(outDir, outName);

    nTotalCh   = opts.nTotalCh;
    storeClass = char(opts.storeClass);
    fallbackADBV = opts.fallbackADBV;
    verbose    = opts.verbose;

    % Validate .ncs presence
    if isempty(dir(fullfile(basePath, 'CSC*.ncs')))
        error('No CSC*.ncs files found in %s', basePath);
    end

    % Channel selection sanity
    allCh = 1:nTotalCh;
    kept_channels = intersect(allCh, unique(keep(:)'));
    if isempty(kept_channels)
        error('No channels to keep after replacement logic.');
    end
    nKept = numel(kept_channels);

    if verbose
        fprintf('  Converting folder: %s\n', basePath);
        fprintf('  Saving to        : %s\n', outFull);
        fprintf('  Kept channels (%d): %s ...\n', nKept, mat2str(kept_channels(1:min(12,end))));
    end

    % ---------- First pass: sizes, sfx, ADBV ----------
    FS = [1 1 1 1 1]; EH = 1; EM = 1;
    headersCell  = cell(1, nKept);
    sfxArr       = nan(1, nKept);
    lenArr       = nan(1, nKept);
    badch_full   = false(1, nTotalCh);
    fileListKept = strings(1, nKept);
    ADBitVoltsK  = nan(1, nKept);

    fprintf('    First pass (scan sizes, sfx, ADBitVolts)\n');
    for i = 1:nKept
        ch = kept_channels(i);
        fname = fullfile(basePath, sprintf('CSC%d.ncs', ch));
        fileListKept(i) = string(fname);
        if ~isfile(fname)
            warning('    Missing file: %s (ch %d). Marking bad.', fname, ch);
            badch_full(ch) = true; lenArr(i) = 0; headersCell{i} = {};
            continue;
        end
        try
            [Timestamps, ~, SampleFrequencies, NValid, Samples, Header] = ...
                Nlx2MatCSC(fname, FS, EH, EM, []);

            blkN = size(Samples,1);
            nv   = min(blkN, max(0, NValid(:)'));
            lenArr(i) = sum(nv);

            % sfx
            sfxCh = mode(double(SampleFrequencies(SampleFrequencies>0)));
            if ~(isfinite(sfxCh) && sfxCh>0)
                sfLine = Header(contains(Header,'SamplingFrequency','IgnoreCase',true));
                if ~isempty(sfLine)
                    tok = regexp(sfLine{1}, 'SamplingFrequency[^0-9eE.\-]*([\-+]?\d+(\.\d+)?([eE][\-+]?\d+)?)', 'tokens', 'once');
                    if ~isempty(tok), sfxCh = str2double(tok{1}); end
                end
            end
            sfxArr(i) = sfxCh;

            % ADBitVolts
            ADBV = NaN;
            k = find(contains(Header,'ADBitVolts','IgnoreCase',true),1,'first');
            if ~isempty(k)
                tok = regexp(Header{k}, 'ADBitVolts[^0-9eE.\-]*([\-+]?\d+(\.\d+)?([eE][\-+]?\d+)?)', 'tokens', 'once');
                if ~isempty(tok), ADBV = str2double(tok{1}); end
            end
            if ~(isfinite(ADBV) && ADBV>0)
                ADBV = fallbackADBV;
                warning('    ADBitVolts missing for CSC%d; using fallback %.12g V/AD', ch, ADBV);
            end
            ADBitVoltsK(i) = ADBV;

            headersCell{i} = Header;

            if verbose
                fprintf('      CSC%-2d: %10d samples @ %g Hz | ADBitVolts=%.12g\n', ch, lenArr(i), sfxArr(i), ADBV);
            end

            % Rough continuity check
            if ~isempty(Timestamps) && isfinite(sfxCh) && sfxCh>0
                expectedStep_us = 512*(1e6/sfxCh);
                dt = diff(double(Timestamps));
                if any(abs(dt - expectedStep_us) > 0.5*expectedStep_us)
                    warning('    Timing irregularity in CSC%d (gaps not interpolated).', ch);
                end
            end
        catch ME
            warning('    Read failure %s (ch %d): %s. Marking bad.', fname, ch, ME.message);
            badch_full(ch) = true; lenArr(i) = 0; headersCell{i} = {}; sfxArr(i) = NaN; ADBitVoltsK(i) = NaN;
        end
    end

    good = (lenArr>0) & isfinite(sfxArr) & sfxArr>0;
    if ~any(good), error('    No valid channels or sampling frequency could be determined.'); end
    sfx = mode(round(sfxArr(good)));

    % ---------- Disk-backed target ----------
    maxN = max(lenArr(good));
    if exist(outFull,'file'), delete(outFull); end
    mf = matfile(outFull, 'Writable', true);
    switch lower(storeClass)
        case 'single', mf.d = single(NaN(nKept, maxN));
        case 'double', mf.d = NaN(nKept, maxN);
        otherwise, error('storeClass must be ''single'' or ''double''.');
    end

    % Meta first
    mf.sfx            = sfx;
    mf.badch          = badch_full;
    mf.chan_labels    = arrayfun(@(k) sprintf('CSC%d', k), 1:nTotalCh, 'UniformOutput', false);
    mf.kept_channels  = kept_channels;
    mf.headersCell    = headersCell;
    mf.units          = 'microvolts';
    meta.sourcePath   = basePath;
    meta.savePath     = outDir;
    meta.createdOn    = datestr(now);
    meta.nTotalCh     = nTotalCh;
    meta.nKept        = nKept;
    meta.reader       = ['Nlx2MatCSC (', mexext, ')'];
    meta.storeClass   = storeClass;
    meta.note         = 'Disk-backed; NaN-padded; per-channel AD→µV scaling during write.';
    meta.fileListKept = fileListKept;
    meta.ADBitVolts   = ADBitVoltsK;
    meta.scaleFactor  = ADBitVoltsK * 1e6; % µV/AD per kept channel
    mf.meta = meta;

    % ---------- Second pass: write scaled data ----------
    fprintf('    Second pass (write µV data)\n');
    t0 = tic;
    for i = 1:nKept
        ch = kept_channels(i);
        if badch_full(ch) || lenArr(i)==0
            fprintf('      CSC%-2d: skipped (bad/missing)\n', ch);
            continue;
        end
        fname = fullfile(basePath, sprintf('CSC%d.ncs', ch));
        [~, ~, ~, NValid, Samples] = Nlx2MatCSC(fname, [1 1 1 1 1], 0, 1, []);
        blkN = size(Samples,1); nRec = size(Samples,2);
        x = nan(1, lenArr(i));
        pos = 1;
        for r = 1:nRec
            nv = min(blkN, max(0, NValid(r)));
            if nv>0
                x(pos:pos+nv-1) = double(Samples(1:nv, r));
                pos = pos + nv;
            end
        end
        % scale to µV for this channel
        sf_uV = ADBitVoltsK(i) * 1e6;
        if ~(isfinite(sf_uV) && sf_uV>0), sf_uV = fallbackADBV * 1e6; end
        x = x * sf_uV;
        switch lower(storeClass)
            case 'single', x = single(x);
            case 'double', x = double(x);
        end
        mf.d(i, 1:numel(x)) = x;

        if mod(i,2)==0 || i==nKept
            elapsed = toc(t0);
            fprintf('      [%3d/%3d] CSC%-2d written | %.1f%% | elapsed %s\n', ...
                i, nKept, ch, 100*i/nKept, duration(0,0,elapsed,"Format","mm:ss"));
        end
    end
    fprintf('    Saved: %s\n', outFull);
end
