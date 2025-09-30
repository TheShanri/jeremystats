function RunLLspikedetector_Folder(rootDir, varargin)
% RunLLspikedetector_Folder
% Batch-run LLspikedetector on converted, disk-backed MAT files (LL_input_*_uV.mat),
% flipping polarity first (multiply by -1), and save outputs next to each input.
%
% Usage:
%   RunLLspikedetector_Folder('E:\LL_ready_outputs')
%   RunLLspikedetector_Folder('E:\LL_ready_outputs', 'llw_sec',0.040,'prc_thr',99.9)
%
% Options (Name,Value):
%   'pattern'       : file pattern to match (default 'LL_input_*_uV.mat')
%   'recurse'       : logical (default true) → search subfolders
%   'llw_sec'       : line-length window (sec), default 0.040
%   'prc_thr'       : percentile threshold, default 99.9
%   'polarityFlip'  : logical (default true) → multiply data by -1 before detect
%   'skipIfExists'  : logical (default true) → if *any* prior LLspikes output exists, skip
%   'verbose'       : logical (default true)
%
% Assumes each input MAT contains:
%   - d              : [rows x samples] (disk-backed ok)
%   - sfx            : sampling frequency (Hz)
%   - badch          : logical(1, nTotalCh) in original indexing (optional but recommended)
%   - kept_channels  : row→original-channel mapping (optional; falls back to 1:nRows)

% ------------------ parse args ------------------
ip = inputParser;
ip.addRequired('rootDir', @(s)ischar(s)||isstring(s));
ip.addParameter('pattern', 'LL_input_*_uV.mat', @(s)ischar(s)||isstring(s));
ip.addParameter('recurse', true, @(x)islogical(x)||ismember(x,[0 1]));
ip.addParameter('llw_sec', 0.040, @(x)isfinite(x)&&x>0);
ip.addParameter('prc_thr', 99.9,  @(x)isfinite(x)&&x>0&&x<100);
ip.addParameter('polarityFlip', true, @(x)islogical(x)||ismember(x,[0 1]));
ip.addParameter('skipIfExists', true, @(x)islogical(x)||ismember(x,[0 1]));
ip.addParameter('verbose', true, @(x)islogical(x)||ismember(x,[0 1]));
ip.parse(rootDir, varargin{:});
opts = ip.Results;
rootDir = char(rootDir);

if ~isfolder(rootDir)
    error('Folder not found: %s', rootDir);
end

% ------------------ discover inputs ------------------
if opts.recurse
    files = dir(fullfile(rootDir, '**', opts.pattern));
else
    files = dir(fullfile(rootDir, opts.pattern));
end
if isempty(files)
    fprintf('No files matching "%s" under: %s\n', opts.pattern, rootDir);
    return;
end

fprintf('Found %d input MAT file(s).\n', numel(files));

% ------------------ process each file ------------------
for k = 1:numel(files)
    inMat = fullfile(files(k).folder, files(k).name);
    [inDir, baseName, ~] = fileparts(inMat);

    % If skip is enabled and any existing output is present, skip
    if opts.skipIfExists
        prior = [dir(fullfile(inDir, sprintf('%s_LLspikes_*.mat', baseName))); ...
                 dir(fullfile(inDir, sprintf('%s_LLspikes_*.csv', baseName)))];
        if ~isempty(prior)
            fprintf('[%3d/%3d] Skipping (already has LLspikes outputs): %s\n', k, numel(files), inMat);
            continue;
        end
    end

    try
        run_one(inMat, opts);
    catch ME
        warning('[%3d/%3d] Failed: %s\n  -> %s', k, numel(files), inMat, ME.message);
    end
end

fprintf('Done.\n');

end % === main ===

% ======================= helpers =======================

function run_one(inMat, opts)
tAll = tic;

if opts.verbose
    fprintf('\nProcessing: %s\n', inMat);
end

% Open as disk-backed matfile
mf = matfile(inMat);

% Verify & load metadata
vars = who(mf);
needD   = any(strcmp(vars,'d'));
needSfx = any(strcmp(vars,'sfx'));
if ~needD || ~needSfx
    error('Input missing required vars (need at least d and sfx).');
end

sfx = mf.sfx;
% badch (optional)
if any(strcmp(vars,'badch'))
    badch_full = mf.badch;
else
    badch_full = [];
end
% kept_channels (optional)
if any(strcmp(vars,'kept_channels'))
    kept_channels = mf.kept_channels;
else
    kept_channels = 1:size(mf,'d',1);
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

% Build badch aligned to data rows
badch_rows = false(1, nRows);
if ~isempty(badch_full) && numel(badch_full) >= max(kept_channels)
    for i = 1:nRows
        badch_rows(i) = logical(badch_full( kept_channels(i) ));
    end
end

% Read data into memory (double) and flip polarity if requested
if opts.verbose
    fprintf('  Loading data into RAM as double%s...\n', tern(opts.polarityFlip,' (will flip)',''));
end

% Make LLspikedetector temp files land beside input
[inDir, baseName, ~] = fileparts(inMat);
oldCWD = pwd;
cd(inDir);
cleanupObj = onCleanup(@() cd(oldCWD));

d = double(mf.d(:,:));
if opts.polarityFlip
    d = -d;
end

% Run LLspikedetector
if opts.verbose
    fprintf('  Running LLspikedetector (llw=%.3f s, prc=%.3f)...\n', opts.llw_sec, opts.prc_thr);
end
[ets, ech] = LLspikedetector(d, sfx, opts.llw_sec, opts.prc_thr, badch_rows);

% Convert indices to seconds
t_on  = ets(:,1) ./ sfx;
t_off = ets(:,2) ./ sfx;
dur_s = t_off - t_on;

% Human-readable channel lists (original channel numbers)
chan_list = cell(size(ech,1),1);
for k = 1:size(ech,1)
    active_rows = find(ech(k,:));
    chan_list{k} = strjoin(arrayfun(@(r) sprintf('CSC%d', kept_channels(r)), ...
                                    active_rows, 'UniformOutput', false), ',');
end

% Assemble table
T = table(ets(:,1), ets(:,2), t_on, t_off, dur_s, chan_list, ...
          'VariableNames', {'on_samp','off_samp','on_sec','off_sec','duration_sec','channels'});

% Save outputs next to input
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
    fprintf('  Done in %s.\n', duration(0,0,toc(tAll),"Format","mm:ss"));
end
end

function cleanup_LLtemps(dirPath)
% LLspikedetector writes big temps to current directory. Remove them.
cand = {'d.mat','L.mat','Lvec.mat','eON.mat','eOFF.mat'};
for i = 1:numel(cand)
    f = fullfile(dirPath, cand{i});
    if exist(f, 'file')
        try, delete(f); catch, end
    end
end
end

function out = tern(cond, a, b)
% tiny ternary helper
if cond, out = a; else, out = b; end
end
