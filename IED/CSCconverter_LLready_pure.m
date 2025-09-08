function CSCconverter_LLready_mex()
% Build LLspikedetector-ready .mat from Neuralynx CSC#.ncs using Nlx2MatCSC (MEX)
% Memory-friendly options: storeClass ('single'|'double'), downsampleFactor (integer)

% --------- USER SETTINGS ----------
reqsPath = fullfile(fileparts(mfilename('fullpath')), 'reqsPath');  % where Nlx2MatCSC.* lives

basePath = 'C:\Users\info\Desktop\Barry\Data\TestIEDData\M13s2aug1\2023-08-01_12-11-26';
nCh      = 64;   % CSC1..CSC64
outName  = 'LL_input_M13s2aug1_2023-08-01_12-11-26_mex_ds.mat';

storeClass       = 'single';   % 'single' (recommended) or 'double'
downsampleFactor = 1;          % 1 = no downsample; try 2,4,8 to reduce RAM
useDecimate      = true;       % true: decimate() (needs Signal Processing Toolbox); false: simple pick-every-N
% ----------------------------------

% --- PATH & MEX CHECKS ---
if isfolder(reqsPath), addpath(reqsPath); end
rehash toolboxcache; clear mex;
nlxPaths = which('-all','Nlx2MatCSC');
if isempty(nlxPaths), error('Nlx2MatCSC not found on path. Ensure .mexw64 is in reqsPath.'); end
if ~any(endsWith(string(nlxPaths), ['.',mexext], 'IgnoreCase',true))
    error('MATLAB is seeing only Nlx2MatCSC.m (help). Ensure Nlx2MatCSC.%s is earlier on the path.', mexext);
end
fprintf('Using Nlx2MatCSC at:\n'); disp(nlxPaths(:));

% --- Containers ---
FS = [1 1 1 1 1];  EH = 1;  EM = 1;  % field flags, extract header, mode
samplesCell = cell(1,nCh);
headersCell = cell(1,nCh);
fileList    = strings(1,nCh);
sfxArr      = nan(1,nCh);
lenArr      = nan(1,nCh);
badch       = false(1,nCh);
ADBV        = nan(1,nCh);

fprintf('Reading CSC files from:\n  %s\n', basePath);

for ch = 1:nCh
    fname = fullfile(basePath, sprintf('CSC%d.ncs', ch));
    fileList(ch) = string(fname);
    if ~isfile(fname)
        warning('Missing file: %s (ch %d). Marking bad.', fname, ch);
        badch(ch) = true; continue;
    end

    try
        [Timestamps, ~, SampleFrequencies, NValid, Samples, Header] = ...
            Nlx2MatCSC(fname, FS, EH, EM, []);

        % ADBitVolts from header
        ADBitVolts = NaN;
        k = find(contains(Header,'ADBitVolts','IgnoreCase',true),1,'first');
        if ~isempty(k)
            tok = regexp(Header{k}, 'ADBitVolts[^0-9eE.\-]*([\-+]?\d+(\.\d+)?([eE][\-+]?\d+)?)','tokens','once');
            if ~isempty(tok), ADBitVolts = str2double(tok{1}); end
        end
        ADBV(ch) = ADBitVolts;

        % Flatten records honoring NumberValidSamples; fill tail with NaN
        blkN = size(Samples,1); nRec = size(Samples,2); % 512 x nRec
        x    = nan(1, blkN*nRec);  % temp double; will cast later
        for r = 1:nRec
            nv = min(blkN, max(0, NValid(r)));
            if nv>0
                idx = (r-1)*blkN + (1:nv);
                x(idx) = double(Samples(1:nv, r));
            end
        end

        % Optional downsample (and adjust sfx)
        sfxCh = mode(double(SampleFrequencies(SampleFrequencies>0)));
        if isnan(sfxCh) || sfxCh<=0
            sfLine = Header(contains(Header,'SamplingFrequency','IgnoreCase',true));
            if ~isempty(sfLine)
                t = regexp(sfLine{1}, 'SamplingFrequency[^0-9eE.\-]*([\-+]?\d+(\.\d+)?([eE][\-+]?\d+)?)','tokens','once');
                if ~isempty(t), sfxCh = str2double(t{1}); end
            end
        end
        if ~isfinite(sfxCh) || sfxCh<=0
            error('Could not determine sampling frequency for %s', fname);
        end

        if downsampleFactor>1
            if useDecimate && exist('decimate','file')
                % IIR decimator with anti-aliasing
                x = decimate(x, downsampleFactor);
            else
                % Simple pick-every-N (fast, but no anti-aliasing)
                x = x(1:downsampleFactor:end);
            end
            sfxCh = sfxCh / downsampleFactor;
        end

        % Optionally scale to Volts
        % (LLspikedetector works fine in AD counts; volts not required)
        % if isfinite(ADBitVolts), x = x * ADBitVolts; end

        % Cast to desired storage class
        switch lower(storeClass)
            case 'single', x = single(x);
            case 'double', x = double(x);
            otherwise, error('storeClass must be ''single'' or ''double''.');
        end

        samplesCell{ch} = x;
        lenArr(ch)      = numel(x);
        sfxArr(ch)      = sfxCh;
        headersCell{ch} = Header;

        fprintf('  CSC%-2d: %10d samples @ %.6g Hz  (ADBitVolts=%s)\n', ...
            ch, numel(x), sfxCh, iff(isfinite(ADBitVolts), num2str(ADBitVolts), 'NA'));

        % Optional continuity check (original, pre-DS step)
        if ~isempty(Timestamps)
            expectedStep_us = 512 * (1e6 / (sfxCh*downsampleFactor)); % step before DS
            dt = diff(double(Timestamps));
            if any(abs(dt - expectedStep_us) > 0.5*expectedStep_us)
                warning('Timing irregularity in %s (ch %d).', fname, ch);
            end
        end

    catch ME
        warning('Failed %s (ch %d): %s. Marking bad.', fname, ch, ME.message);
        badch(ch) = true; samplesCell{ch} = []; lenArr(ch)=NaN; sfxArr(ch)=NaN;
    end
end

% Unified sampling frequency (mode across good channels)
good = ~badch & isfinite(sfxArr) & sfxArr>0;
if ~any(good), error('No valid channels or sampling freq.'); end
sfx = mode(round(sfxArr(good)));
if any(abs(sfxArr(good) - sfx) > 1e-6)
    warning('Slight sfx variance across channels. Using mode = %.6g Hz.', sfx);
end

% Compute final size and allocate d with chosen class
maxN = max(lenArr(good));
bytesPer = strcmpi(storeClass,'single')*4 + strcmpi(storeClass,'double')*8;
approxGB = (nCh*maxN*bytesPer)/1e9;
fprintf('\nAllocating d: %d x %d (%s) ~ %.2f GB\n', nCh, maxN, storeClass, approxGB);

d = nan(nCh, maxN, storeClass);
for ch = 1:nCh
    xi = samplesCell{ch};
    if isempty(xi), continue; end
    d(ch,1:numel(xi)) = xi;   % trailing remains NaN
end

chan_labels = arrayfun(@(k) sprintf('CSC%d', k), 1:nCh, 'UniformOutput', false);

meta.basePath     = basePath;
meta.createdOn    = datestr(now);
meta.nCh          = nCh;
meta.reader       = ['Nlx2MatCSC (', mexext, ')'];
meta.storeClass   = storeClass;
meta.downsample   = downsampleFactor;
meta.note         = 'NaN-padded to equalize length.';
meta.fileList     = fileList;
meta.ADBitVolts   = ADBV;

save(fullfile(basePath, outName), 'd', 'sfx', 'badch', 'chan_labels', 'headersCell', 'meta', '-v7.3');

fprintf('\nSaved LL-ready file:\n  %s\n', fullfile(basePath, outName));
fprintf('\nExample:\n  load(''%s'');\n  [ets,ech] = LLspikedetector(double(d), sfx, 0.04, 99.9, badch);\n', fullfile(basePath, outName));
end

% -------- helpers --------
function s = iff(cond, a, b)
if cond, s=a; else, s=b; end
end
