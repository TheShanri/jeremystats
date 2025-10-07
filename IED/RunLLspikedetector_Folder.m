function RunLLspikedetector_Folder(rootDir, varargin)
% RunLLspikedetector_Folder
% Batch-run LLspikedetector on LL_input_*_uV.mat files (recursively).
% - Flips polarity (multiply by -1) before detection
% - Loads as SINGLE by default to halve memory
% - Checks/sets path to LLspikedetector via 'llPath'
% - Skips files that already have outputs
%
% Usage:
%   RunLLspikedetector_Folder('E:\LL_ready_outputs', ...
%       'llPath','C:\path\to\LLspike', 'precision','single', ...
%       'llw_sec',0.040,'prc_thr',99.9);

% ------------------ parse args ------------------
ip = inputParser;
ip.addRequired('rootDir', @(s)ischar(s)||isstring(s));
ip.addParameter('pattern', 'LL_input_*_uV.mat', @(s)ischar(s)||isstring(s));
ip.addParameter('recurse', true, @(x)islogical(x)||ismember(x,[0 1]));
ip.addParameter('llw_sec', 0.040, @(x)isfinite(x)&&x>0);
ip.addParameter('prc_thr', 99.9,  @(x)isfinite(x)&&x>0&&x<100);
ip.addParameter('polarityFlip', true, @(x)islogical(x)||ismember(x,[0 1]));
ip.addParameter('skipIfExists', true, @(x)islogical(x)||ismember(x,[0 1]));
ip.addParameter('precision','single', @(s) any(strcmpi(s,{'single','double'})));
ip.addParameter('llPath','', @(s)ischar(s)||isstring(s));      % Folder that contains LLspikedetector
ip.addParameter('verbose', true, @(x)islogical(x)||ismember(x,[0 1]));
ip.addParameter('chunkCols', 2e6, @(x)isfinite(x)&&x>=1);      % columns per chunk when reading from matfile
ip.parse(rootDir, varargin{:});
opts = ip.Results;
rootDir = char(rootDir);

if ~isfolder(rootDir), error('Folder not found: %s', rootDir); end

% ------------------ ensure LLspikedetector on path ------------------
if ~isempty(opts.llPath) && isfolder(opts.llPath)
    addpath(char(opts.llPath));
end
if exist('LLspikedetector','file') ~= 2 && exist('LLspikedetector','file') ~= 3
    error(['LLspikedetector not found on MATLAB path.\n' ...
           'Provide its folder via the ''llPath'' argument, e.g.:\n' ...
           '  RunLLspikedetector_Folder(''%s'',''llPath'',''C:\\path\\to\\LLspikedetector'')'], rootDir);
end

% ------------------ discover inputs ------------------
if opts.recurse
    files = dir(fullfile(rootDir, '**', opts.pattern));
else
    files = dir(fullfile(rootDir, opts.pattern));
end
files = files(:);

if isempty(files)
    fprintf('No files matching "%s" under: %s\n', opts.pattern, rootDir);
    return;
end

fprintf('Found %d input MAT file(s).\n', numel(files));

% ------------------ process each file ------------------
for k = 1:numel(files)
    inMat = fullfile(files(k).folder, files(k).name);
    [inDir, baseName, ~] = fileparts(inMat);

    % Skip if outputs already present
    if opts.skipIfExists
        prior = [dir(fullfile(inDir, sprintf('%s_LLspikes_*.mat', baseName))); ...
                 dir(fullfile(inDir, sprintf('%s_LLspikes_*.csv', baseName)))];
        if ~isempty(prior)
            fprintf('[%3d/%3d] Skipping (already has LLspikes outputs): %s\n', k, numel(files), inMat);
            continue;
        end
    end

    try
        run_one(inMat, opts, k, numel(files));
    catch ME
        warning('[%3d/%3d] Failed: %s\n  -> %s', k, numel(files), inMat, ME.message);
    end
end

fprintf('Done.\n');

end % === main ===


% ======================= helpers =======================

function run_one(inMat, opts, idx, nTotal)
tAll = tic;

if opts.verbose
    fprintf('\nProcessing: %s\n', inMat);
end

% Open as disk-backed matfile
mf = matfile(inMat);

% Verify & load metadata
vars = who(mf);
if ~any(strcmp(vars,'d')) || ~any(strcmp(vars,'sfx'))
    error('Input missing required vars (need at least d and sfx).');
end
sfx = mf.sfx;

% badch (optional)
if any(strcmp(vars,'badch')), badch_full = mf.badch; else, badch_full = []; end
% kept_channels (optional)
if any(strcmp(vars,'kept_channels')), kept_channels = mf.kept_channels;
else, kept_channels = 1:size(mf,'d',1);
end

nRows = size(mf, 'd', 1);
nCol  = size(mf, 'd', 2);

if opts.verbose
    fprintf('  d: %d rows x %d samples | sfx: %.6g Hz\n', nRows, nCol, sfx);
    if ~isempty(badch_full)
        fprintf('  badch available (length %d). ', numel(badch_full));
    else
        fprintf('  badch not found; will run with no bad-channel mask. ');
    end
    fprintf('Rows map to original channels: %s\n', mat2str(kept_channels));
end

% Build row-aligned bad-channel mask
badch_rows = false(1, nRows);
if ~isempty(badch_full) && numel(badch_full) >= max(kept_channels)
    for i = 1:nRows
        badch_rows(i) = logical(badch_full( kept_channels(i) ));
    end
end

% -------- Preflight memory check + chunked read as SINGLE by default --------
wantSingle = strcmpi(opts.precision,'single');
bytesPer   = 4*(wantSingle) + 8*(~wantSingle);
needBytes  = double(nRows) * double(nCol) * bytesPer;

maxBytes = NaN;
if ispc && exist('memory','file')==2
    try
        mem = memory;
        maxBytes = mem.MaxPossibleArrayBytes;
    catch
        maxBytes = NaN;
    end
end

if ~isnan(maxBytes) && needBytes > maxBytes
    % Try to salvage by switching to single if user asked for double
    if ~wantSingle
        fprintf('  Preflight: double would need %.1f GB > max %.1f GB. Retrying with single.\n', needBytes/1e9, maxBytes/1e9);
        wantSingle = true;
        bytesPer   = 4;
        needBytes  = double(nRows) * double(nCol) * bytesPer;
    end
end

if ~isnan(maxBytes) && needBytes > maxBytes
    errMsg = sprintf( ...
        'Requested %dx%d (%.1fGB %s) exceeds MaxPossibleArrayBytes (%.1fGB). Consider processing fewer channels/time.', ...
        nRows, nCol, needBytes/1e9, tern(wantSingle,'single','double'), maxBytes/1e9);
    error(errMsg);
end


% Make LLspikedetector temp files land beside input
[inDir, baseName, ~] = fileparts(inMat);
oldCWD = pwd; cd(inDir);
cleanupCWD = onCleanup(@() cd(oldCWD));

% Allocate output array in desired precision and fill in chunks
if wantSingle
    d = zeros(nRows, nCol, 'single');
else
    d = zeros(nRows, nCol, 'double');
end

if opts.verbose
    fprintf('  Loading data into RAM as %s%s...\n', class(d), tern(opts.polarityFlip,' (will flip)',''));
end

col = 1;
chunkCols = min(nCol, round(opts.chunkCols));
while col <= nCol
    j1 = min(nCol, col + chunkCols - 1);
    block = mf.d(:, col:j1);           % read as stored type (likely single)
    if opts.polarityFlip, block = -block; end
    if wantSingle && ~isa(block,'single'), block = single(block); end
    if ~wantSingle && ~isa(block,'double'), block = double(block); end
    d(:, col:j1) = block;
    col = j1 + 1;
end

% -------- Run LLspikedetector --------
if opts.verbose
    fprintf('  Running LLspikedetector (llw=%.3f s, prc=%.3f)...\n', opts.llw_sec, opts.prc_thr);
end
[ets, ech] = LLspikedetector(d, sfx, opts.llw_sec, opts.prc_thr, badch_rows);

% -------- Summaries --------
t_on  = ets(:,1) ./ sfx;
t_off = ets(:,2) ./ sfx;
dur_s = t_off - t_on;

chan_list = cell(size(ech,1),1);
for k = 1:size(ech,1)
    active_rows = find(ech(k,:));
    chan_list{k} = strjoin(arrayfun(@(r) sprintf('CSC%d', kept_channels(r)), ...
                                    active_rows, 'UniformOutput', false), ',');
end

T = table(ets(:,1), ets(:,2), t_on, t_off, dur_s, chan_list, ...
          'VariableNames', {'on_samp','off_samp','on_sec','off_sec','duration_sec','channels'});

% -------- Save outputs next to input --------
stamp  = datestr(now, 'yyyymmdd_HHMMSS');
flipTag = tern(opts.polarityFlip, '_flip','');
outMat = fullfile(inDir, sprintf('%s_LLspikes%s_%s.mat', baseName, flipTag, stamp));
outCsv = fullfile(inDir, sprintf('%s_LLspikes%s_%s.csv', baseName, flipTag, stamp));

params.llw_sec       = opts.llw_sec;
params.prc_thr       = opts.prc_thr;
params.sfx           = sfx;
params.kept_channels = kept_channels;
params.badch_rows    = badch_rows;
params.polarityFlip  = logical(opts.polarityFlip);
params.precision     = class(d);
params.sourceMat     = inMat;

save(outMat, 'ets', 'ech', 'T', 'params', '-v7.3');
writetable(T, outCsv);

if opts.verbose
    fprintf('  Detected %d spike event(s).\n', size(ets,1));
    fprintf('  Saved:\n    MAT: %s\n    CSV: %s\n', outMat, outCsv);
end

% Clean up LLspikedetector temp files in the input folder
cleanup_LLtemps(inDir);

if opts.verbose
    fprintf('  [%d/%d] Done in %s.\n', idx, nTotal, duration(0,0,toc(tAll),"Format","mm:ss"));
end
end

function cleanup_LLtemps(dirPath)
% LLspikedetector writes big temps to current directory. Remove them.
cand = {'d.mat','L.mat','Lvec.mat','eON.mat','eOFF.mat'};
for i = 1:numel(cand)
    f = fullfile(dirPath, cand{i});
    if exist(f, 'file')
        try
            delete(f);
        catch
            % ignore
        end
    end
end
end


function out = tern(cond, a, b)
% tiny ternary helper
if cond, out = a; else, out = b; end
end
