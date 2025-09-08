function CSCconverter_LLready_pure()
% Build LLspikedetector-ready .mat from Neuralynx CSC#.ncs files WITHOUT the MEX.
% - Reads ASCII header + fixed-size binary records for each file
% - Respects NumberOfValidSamples per 512-sample block (pads invalid with NaN)
% - Stacks channels into d (channels x time), NaN-pads shorter channels
% - Derives a unified sampling frequency 'sfx' from file metadata
% - Saves: d, sfx, badch, chan_labels, headersCell, meta  (-v7.3)

% --------- USER SETTINGS ----------
basePath = 'C:\Users\info\Desktop\Barry\jeremystats\Hazing\TestIEDData\M13s2aug1\2023-08-01_12-11-26';
nCh      = 64;  % expects CSC1.ncs ... CSC64.ncs
outName  = 'LL_input_M13s2aug1_2023-08-01_12-11-26_pure.mat';
scaleToVolts = false;  % if true and header has -ADBitVolts, scales Samples to Volts
% ----------------------------------

samplesCell   = cell(1,nCh);
headersCell   = cell(1,nCh);
fileList      = strings(1,nCh);
sfxArr        = nan(1,nCh);
nSamplesArr   = nan(1,nCh);
badch         = false(1,nCh);

fprintf('Reading (pure MATLAB) CSC files from:\n  %s\n', basePath);

for ch = 1:nCh
    fname = fullfile(basePath, sprintf('CSC%d.ncs', ch));
    fileList(ch) = string(fname);

    if ~isfile(fname)
        warning('Missing file: %s. Marking channel %d as bad.', fname, ch);
        badch(ch) = true;
        continue;
    end

    try
        [Timestamps, ChannelNumbers, SampleFrequencies, NumberValidSamples, Samples, Header, info] = ...
            read_ncs_minimal(fname, 'ScaleToVolts', scaleToVolts);

        % Flatten Samples to a single row vector, honoring NumberValidSamples per block.
        % We convert each 512-sample block: keep first Nvalid, set the rest to NaN.
        blkN   = size(Samples,1);   % 512
        nRec   = size(Samples,2);
        x      = nan(1, blkN*nRec);
        for r = 1:nRec
            nvalid = min(blkN, max(0, NumberValidSamples(r)));
            if nvalid > 0
                offs = (r-1)*blkN;
                x(offs + (1:nvalid)) = double(Samples(1:nvalid, r));
            end
        end

        samplesCell{ch} = x;
        nSamplesArr(ch) = numel(x);

        % Prefer modal per-record SampleFrequencies; fall back to header key
        if ~isempty(SampleFrequencies)
            sfxArr(ch) = mode(SampleFrequencies(SampleFrequencies > 0));
        end
        if ~(isfinite(sfxArr(ch)) && sfxArr(ch) > 0)
            try
                sfLine = Header(contains(Header, 'SamplingFrequency', 'IgnoreCase', true));
                if ~isempty(sfLine)
                    tokens = regexp(sfLine{1}, 'SamplingFrequency[^0-9eE.\-]*([\-+]?\d+(\.\d+)?([eE][\-+]?\d+)?)', 'tokens', 'once');
                    if ~isempty(tokens); sfxArr(ch) = str2double(tokens{1}); end
                end
            catch
            end
        end

        headersCell{ch} = Header;

        fprintf('  Loaded CSC%d: %d samples @ ~%.6g Hz (ADBitVolts=%s)\n', ...
            ch, numel(x), sfxArr(ch), ternary(isfinite(info.ADBitVolts), num2str(info.ADBitVolts), 'NA'));

        % Optional continuity check
        if ~isempty(Timestamps) && isfinite(sfxArr(ch)) && sfxArr(ch) > 0
            expectedStep_us = 512 * (1e6 / sfxArr(ch));
            dtBlocks = diff(Timestamps); % microseconds between block starts
            if any(abs(dtBlocks - expectedStep_us) > 0.5 * expectedStep_us)
                warning('Timing irregularity in %s (ch %d). Internal gaps not interpolated.', fname, ch);
            end
        end

        % If scaling to Volts is requested and header contains ADBitVolts:
        if scaleToVolts && isfinite(info.ADBitVolts)
            samplesCell{ch} = samplesCell{ch} * info.ADBitVolts;
        end

    catch ME
        warning('Failed to read %s (ch %d): %s. Marking as bad.', fname, ch, ME.message);
        badch(ch) = true;
        samplesCell{ch} = [];
        headersCell{ch} = {};
        sfxArr(ch) = NaN;
        nSamplesArr(ch) = NaN;
    end
end

% Unified sampling frequency (mode across good channels)
goodSfx = sfxArr(~badch & isfinite(sfxArr) & sfxArr > 0);
if isempty(goodSfx)
    error('Could not determine sampling frequency from any channel.');
end
sfx = mode(round(goodSfx));
if any(abs(goodSfx - sfx) > 1e-6)
    warning('Sample frequencies vary slightly across channels. Using mode = %.6g Hz.', sfx);
end

% Build channels x time with NaN padding to max length
maxN = max(nSamplesArr(~badch));
d    = nan(nCh, maxN, 'double');
for ch = 1:nCh
    xi = samplesCell{ch};
    if isempty(xi), continue; end
    fillN = min(numel(xi), maxN);
    d(ch,1:fillN) = double(xi(1:fillN));
end

chan_labels = arrayfun(@(k) sprintf('CSC%d', k), 1:nCh, 'UniformOutput', false);

meta.basePath     = basePath;
meta.createdOn    = datestr(now);
meta.nCh          = nCh;
meta.reader       = 'read_ncs_minimal (pure MATLAB)';
meta.scaleToVolts = scaleToVolts;
meta.note         = 'Data padded with NaNs to equalize length. Internal gaps not filled.';
meta.fileList     = fileList;

save(fullfile(basePath, outName), 'd', 'sfx', 'badch', 'chan_labels', 'headersCell', 'meta', '-v7.3');

fprintf('\nSaved LL-ready file:\n  %s\n', fullfile(basePath, outName));
fprintf('\nExample usage:\n  load(''%s'');\n  [ets, ech] = LLspikedetector(d, sfx, 0.04, 99.9, badch);\n', fullfile(basePath, outName));
end

% ===================== Local helpers =====================

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end

function [Timestamps, ChannelNumbers, SampleFrequencies, NumberValidSamples, Samples, Header, info] = read_ncs_minimal(filename, varargin)
% Pure-MATLAB reader for Neuralynx .ncs (CSC) files (little-endian).
% Returns arrays like Nlx2MatCSC for ExtractMode=1.
% Name-Value: 'ScaleToVolts' (logical) – only parsed here to keep signature parity; scaling done in caller.

p = inputParser;
p.addParameter('ScaleToVolts', false, @(x)islogical(x)&&isscalar(x));
p.parse(varargin{:});
% scaleToVolts = p.Results.ScaleToVolts;  % handled in caller

fid = fopen(filename, 'r', 'ieee-le');  % little-endian
if fid < 0, error('Cannot open file: %s', filename); end

% --- Read ASCII header until ENDHEADER
Header = {};
while true
    tline = fgetl(fid);
    if ~ischar(tline)
        fclose(fid);
        error('Unexpected EOF while reading header in %s', filename);
    end
    Header{end+1,1} = tline; %#ok<AGROW>
    if contains(tline, 'ENDHEADER', 'IgnoreCase', true), break; end
end

% Parse ADBitVolts (if present)
ADBitVolts = NaN;
try
    k = find(contains(Header, 'ADBitVolts', 'IgnoreCase', true), 1, 'first');
    if ~isempty(k)
        tok = regexp(Header{k}, 'ADBitVolts[^0-9eE.\-]*([\-+]?\d+(\.\d+)?([eE][\-+]?\d+)?)', 'tokens', 'once');
        if ~isempty(tok), ADBitVolts = str2double(tok{1}); end
    end
catch
end
info.ADBitVolts = ADBitVolts;

% --- Determine record count
posAfterHeader = ftell(fid);
fseek(fid, 0, 'eof'); fileSize = ftell(fid);
fseek(fid, posAfterHeader, 'bof');

recBytes = 8 + 4 + 4 + 4 + 512*2; % 1044 bytes
nRec = floor((fileSize - posAfterHeader) / recBytes);
if nRec < 1
    fclose(fid);
    error('No records found in %s', filename);
end

% --- Preallocate
Timestamps          = zeros(1, nRec, 'double');
ChannelNumbers      = zeros(1, nRec, 'double');
SampleFrequencies   = zeros(1, nRec, 'double');
NumberValidSamples  = zeros(1, nRec, 'double');
Samples             = zeros(512, nRec, 'int16');

% --- Read loop
for i = 1:nRec
    Timestamps(i)         = fread(fid, 1, 'int64=>double');
    ChannelNumbers(i)     = fread(fid, 1, 'int32=>double');
    SampleFrequencies(i)  = fread(fid, 1, 'int32=>double');
    NumberValidSamples(i) = fread(fid, 1, 'int32=>double');
    Samples(:,i)          = fread(fid, 512, 'int16=>int16');
end

fclose(fid);
