function Pipeline_Main(inputFolder, varargin)
% Pipeline_Main — runs all sub-pipelines, builds TWO compact triptychs
% (SOLID & SPUTTER) at native resolution, plus a merged stats CSV.
%
% Triptych columns (left → center → right):
%   LEFT  : [VoltageRaster_EventsAvg, CSD_CenterSlices_Waveform_AvgGroups, Spectrogram_Waveform_Stacked_ThirdEvent]  (stacked vertically)
%   CENTER: [EventStacks_ampWidth_Avg]  (the long one)
%   RIGHT : [CSDRaster_Avg, CSD_TimeAvgSlices_Waveforms_AvgGroups]          (stacked vertically)
%
% Robust to missing images/CSVs (warns and continues).
% ---------- 0. INITIAL SETUP & LOGGING ----------
fprintf('\n========================================================\n');
fprintf('===== Pipeline_Main STARTING =====\n');
fprintf('========================================================\n');
fprintf('Timestamp: %s\n', datetime('now'));
fprintf('Input Folder: %s\n', inputFolder);

% --- MODIFICATION: Auto-detect .mat file in PARENT folder ---
[parentFolder, ~] = fileparts(inputFolder);
matFiles = dir(fullfile(parentFolder, '*.mat'));

if isempty(matFiles)
    fprintf('\n  ERROR: No .mat file found in parent directory: %s\n', parentFolder);
    fprintf('  Pipeline stopping.\n');
    fprintf('========================================================\n');
    return; % Stop the function
end

% Use the first .mat file found
dataMatPath = fullfile(matFiles(1).folder, matFiles(1).name);
fprintf('Data MAT Path: %s (Auto-detected in parent folder)\n', dataMatPath);
% --- END MODIFICATION ---


% ---------- Output hub ----------
masterOutDir = fullfile(inputFolder, 'Pipeline Output');
if ~exist(masterOutDir, 'dir'), mkdir(masterOutDir); end
triptychSOLID   = fullfile(masterOutDir, 'Master_Compact_SOLID.png');
triptychSPUTTER = fullfile(masterOutDir, 'Master_Compact_SPUTTER.png');
masterCSV       = fullfile(masterOutDir, 'Master_Stats.csv');

fprintf('Master Output Dir: %s\n', masterOutDir);
fprintf('Master SOLID PNG: %s\n', triptychSOLID);
fprintf('Master SPUTTER PNG: %s\n', triptychSPUTTER);
fprintf('Master STATS CSV: %s\n', masterCSV);
fprintf('--------------------------------------------------------\n\n');


% ---------- 0) ThetaRaster (LEFT, bottom) ----------
fprintf('===== [0] RUNNING ThetaRaster_Pipeline =====\n');
thetaRes = [];
try
    thetaRes = ThetaRaster_Pipeline(inputFolder, varargin{:});
    fprintf('  [0] SUCCESS: ThetaRaster_Pipeline completed.\n');
    if isstruct(thetaRes) && isfield(thetaRes, 'pngSolid')
        fprintf('      -> PNG: %s\n', getFieldSafe(thetaRes, 'pngSolid'));
        fprintf('      -> PDF: %s\n', getFieldSafe(thetaRes, 'pdfPath'));
    end
catch ME
    fprintf('  [0] FAILED: ThetaRaster_Pipeline.\n');
    warning(ME.identifier, 'ThetaRaster_Pipeline failed: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

% ---------- 1) EventStacks (CENTER) ----------
fprintf('===== [1] RUNNING EventStacks_ampWidth_Avg_Pipeline =====\n');
evtStacksRes = [];
try
    evtStacksRes = EventStacks_ampWidth_Avg_Pipeline(inputFolder, dataMatPath, varargin{:});
    fprintf('  [1] SUCCESS: EventStacks_ampWidth_Avg_Pipeline completed.\n');
    if isstruct(evtStacksRes) && isfield(evtStacksRes, 'pngSolid')
        fprintf('      -> SOLID PNG: %s\n', getFieldSafe(evtStacksRes, 'pngSolid'));
        fprintf('      -> SOLID PDF: %s\n', getFieldSafe(evtStacksRes, 'pdfSolid'));
        fprintf('      -> SPUTTER PNG: %s\n', getFieldSafe(evtStacksRes, 'pngSputter'));
        fprintf('      -> SPUTTER PDF: %s\n', getFieldSafe(evtStacksRes, 'pdfSputter'));
        fprintf('      -> STATS CSV: %s\n', getFieldSafe(evtStacksRes, 'statsCSV'));
    end
catch ME
    fprintf('  [1] FAILED: EventStacks_ampWidth_Avg_Pipeline.\n');
    warning(ME.identifier, 'EventStacks_ampWidth_Avg_Pipeline failed: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

% ---------- 2) Voltage Raster (LEFT) ----------
fprintf('===== [2] RUNNING VoltageRaster_EventsAvg_Pipeline =====\n');
voltRasterRes = [];
try
    voltRasterRes = VoltageRaster_EventsAvg_Pipeline(inputFolder, dataMatPath, varargin{:});
    fprintf('  [2] SUCCESS: VoltageRaster_EventsAvg_Pipeline completed.\n');
    if isstruct(voltRasterRes) && isfield(voltRasterRes, 'pngSolid')
        fprintf('      -> SOLID PNG: %s\n', getFieldSafe(voltRasterRes, 'pngSolid'));
        fprintf('      -> SOLID PDF: %s\n', getFieldSafe(voltRasterRes, 'pdfSolid'));
        fprintf('      -> SPUTTER PNG: %s\n', getFieldSafe(voltRasterRes, 'pngSputter'));
        fprintf('      -> SPUTTER PDF: %s\n', getFieldSafe(voltRasterRes, 'pdfSputter'));
        fprintf('      -> STATS CSV: %s\n', getFieldSafe(voltRasterRes, 'statsCSV'));
    end
catch ME
    fprintf('  [2] FAILED: VoltageRaster_EventsAvg_Pipeline.\n');
    warning(ME.identifier, 'VoltageRaster_EventsAvg_Pipeline failed: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

% ---------- 3) CSD Raster (RIGHT) ----------
fprintf('===== [3] RUNNING CSDRaster_Avg_Pipeline =====\n');
csdRasterRes = [];
try
    csdRasterRes = CSDRaster_Avg_Pipeline(inputFolder, dataMatPath, varargin{:});
    fprintf('  [3] SUCCESS: CSDRaster_Avg_Pipeline completed.\n');
    if isstruct(csdRasterRes) && isfield(csdRasterRes, 'pngSolid')
        fprintf('      -> SOLID PNG: %s\n', getFieldSafe(csdRasterRes, 'pngSolid'));
        fprintf('      -> SOLID PDF: %s\n', getFieldSafe(csdRasterRes, 'pdfSolid'));
        fprintf('      -> SPUTTER PNG: %s\n', getFieldSafe(csdRasterRes, 'pngSputter'));
        fprintf('      -> SPUTTER PDF: %s\n', getFieldSafe(csdRasterRes, 'pdfSputter'));
        fprintf('      -> STATS CSV: %s\n', getFieldSafe(csdRasterRes, 'statsCSV'));
    end
catch ME
    fprintf('  [3] FAILED: CSDRaster_Avg_Pipeline.\n');
    warning(ME.identifier, 'CSDRaster_Avg_Pipeline failed: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

% ---------- 4) CSD Center Slices + Vertical Waveforms (LEFT) ----------
fprintf('===== [4] RUNNING CSD_CenterSlices_Waveform_AvgGroups_Pipeline =====\n');
csdSlicesRes = [];
try
    csdSlicesRes = CSD_CenterSlices_Waveform_AvgGroups_Pipeline(inputFolder, dataMatPath, varargin{:});
    fprintf('  [4] SUCCESS: CSD_CenterSlices_Waveform_AvgGroups_Pipeline completed.\n');
    if isstruct(csdSlicesRes) && isfield(csdSlicesRes, 'pngSolid')
        fprintf('      -> SOLID PNG: %s\n', getFieldSafe(csdSlicesRes, 'pngSolid'));
        fprintf('      -> SOLID PDF: %s\n', getFieldSafe(csdSlicesRes, 'pdfSolid'));
        fprintf('      -> SPUTTER PNG: %s\n', getFieldSafe(csdSlicesRes, 'pngSputter'));
        fprintf('      -> SPUTTER PDF: %s\n', getFieldSafe(csdSlicesRes, 'pdfSputter'));
        fprintf('      -> STATS CSV: %s\n', getFieldSafe(csdSlicesRes, 'statsCSV'));
    end
catch ME
    fprintf('  [4] FAILED: CSD_CenterSlices_Waveform_AvgGroups_Pipeline.\n');
    warning(ME.identifier, 'CSD_CenterSlices_Waveform_AvgGroups_Pipeline failed: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

% ---------- 5) CSD Time-Avg Slices + Vertical Waveforms (RIGHT) ----------
fprintf('===== [5] RUNNING CSD_TimeAvgSlices_Waveforms_AvgGroups_Pipeline =====\n');
csdTimeAvgRes = [];
try
    csdTimeAvgRes = CSD_TimeAvgSlices_Waveforms_AvgGroups_Pipeline(inputFolder, dataMatPath, varargin{:});
    fprintf('  [5] SUCCESS: CSD_TimeAvgSlices_Waveforms_AvgGroups_Pipeline completed.\n');
    if isstruct(csdTimeAvgRes) && isfield(csdTimeAvgRes, 'pngSolid')
        fprintf('      -> SOLID PNG: %s\n', getFieldSafe(csdTimeAvgRes, 'pngSolid'));
        fprintf('      -> SOLID PDF: %s\n', getFieldSafe(csdTimeAvgRes, 'pdfSolid'));
        fprintf('      -> SPUTTER PNG: %s\n', getFieldSafe(csdTimeAvgRes, 'pngSputter'));
        fprintf('      -> SPUTTER PDF: %s\n', getFieldSafe(csdTimeAvgRes, 'pdfSputter'));
        fprintf('      -> STATS CSV: %s\n', getFieldSafe(csdTimeAvgRes, 'statsCSV'));
    end
catch ME
    fprintf('  [5] FAILED: CSD_TimeAvgSlices_Waveforms_AvgGroups_Pipeline.\n');
    warning(ME.identifier, 'CSD_TimeAvgSlices_Waveforms_AvgGroups_Pipeline failed: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

% ---------- 6) Spectrogram + Waveform (LEFT, bottom) ----------
fprintf('===== [6] RUNNING Spectrogram_Waveform_Stacked_ThirdEvent_Pipeline =====\n');
spec3rdRes = [];
try
    spec3rdRes = Spectrogram_Waveform_Stacked_ThirdEvent_Pipeline(inputFolder, dataMatPath, varargin{:});
    fprintf('  [6] SUCCESS: Spectrogram_Waveform_Stacked_ThirdEvent_Pipeline completed.\n');
    if isstruct(spec3rdRes) && isfield(spec3rdRes, 'pngSolid')
        fprintf('      -> SOLID PNG: %s\n', getFieldSafe(spec3rdRes, 'pngSolid'));
        fprintf('      -> SOLID PDF: %s\n', getFieldSafe(spec3rdRes, 'pdfSolid'));
        fprintf('      -> SPUTTER PNG: %s\n', getFieldSafe(spec3rdRes, 'pngSputter'));
        fprintf('      -> SPUTTER PDF: %s\n', getFieldSafe(spec3rdRes, 'pdfSputter'));
        % No stats CSV for this module
    end
catch ME
    fprintf('  [6] FAILED: Spectrogram_Waveform_Stacked_ThirdEvent_Pipeline.\n');
    warning(ME.identifier, 'Spectrogram_Waveform_Stacked_ThirdEvent_Pipeline failed: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');


% ---------- Build SOLID triptych ----------
fprintf('===== [7] ASSEMBLING Master_Compact_SOLID.png =====\n');
fprintf('  Target path: %s\n', triptychSOLID);
try
    png_volt_sol   = getFileIfExists(getFieldSafe(voltRasterRes,'pngSolid'));
    png_slice_sol  = getFileIfExists(getFieldSafe(csdSlicesRes,'pngSolid'));
    png_theta_sol  = getFileIfExists(getFieldSafe(thetaRes,    'pngSolid'));
    png_spec_sol   = getFileIfExists(getFieldSafe(spec3rdRes, 'pngSolid'));
    
    png_stack_sol  = getFileIfExists(getFieldSafe(evtStacksRes,'pngSolid'));
    
    png_csdr_sol   = getFileIfExists(getFieldSafe(csdRasterRes,'pngSolid'));
    png_timeavg_sol= getFileIfExists(getFieldSafe(csdTimeAvgRes,'pngSolid'));

    fprintf('  Gathering SOLID files:\n');
    fprintf('    LEFT col 1 (VoltRaster): %s\n',   tern(png_volt_sol=="","",png_volt_sol));
    fprintf('    LEFT col 2 (CSDSlices): %s\n',    tern(png_slice_sol=="","",png_slice_sol));
    fprintf('    LEFT col 3 (Theta): %s\n',        tern(png_theta_sol=="","",png_theta_sol));
    fprintf('    LEFT col 4 (Spectrogram): %s\n',  tern(png_spec_sol=="","",png_spec_sol));
    fprintf('    CENTER col (EvtStacks): %s\n',    tern(png_stack_sol=="","",png_stack_sol));
    fprintf('    RIGHT col 1 (CSDRaster): %s\n',   tern(png_csdr_sol=="","",png_csdr_sol));
    fprintf('    RIGHT col 2 (CSDTimeAvg): %s\n',  tern(png_timeavg_sol=="","",png_timeavg_sol));

    colLeft_SOL = stackVerticalHiRes({png_volt_sol, png_slice_sol, png_theta_sol, png_spec_sol}, 6);   % spectrogram at bottom-left
    colCtr_SOL  = png_stack_sol;
    colRight_SOL= stackVerticalHiRes({png_csdr_sol, png_timeavg_sol}, 6);

    cols_SOL = filterNonEmpty({colLeft_SOL, colCtr_SOL, colRight_SOL});
    if isempty(cols_SOL)
        fprintf('  [7] FAILED: No valid SOLID PNGs were found to assemble.\n');
        warning('Pipeline:NoSolidPNGs', 'No SOLID images found; SOLID compact montage not created.');
    else
        fprintf('  [7] Assembling %d columns...\n', numel(cols_SOL));
        composeColumnsHiRes(cols_SOL, triptychSOLID, 10);
        fprintf('  [7] SUCCESS: Master SOLID compact montage saved: %s\n', triptychSOLID);
    end
catch ME
    fprintf('  [7] FAILED: Assembly of SOLID triptych.\n');
    warning(ME.identifier, 'Failed to build SOLID compact montage: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

% ---------- Build SPUTTER triptych ----------
fprintf('===== [8] ASSEMBLING Master_Compact_SPUTTER.png =====\n');
fprintf('  Target path: %s\n', triptychSPUTTER);
try
    png_volt_spu   = getFileIfExists(getFieldSafe(voltRasterRes,'pngSputter'));
    png_slice_spu  = getFileIfExists(getFieldSafe(csdSlicesRes,'pngSputter'));
    png_theta_spu  = getFileIfExists(getFieldSafe(thetaRes,    'pngSputter'));
    png_spec_spu   = getFileIfExists(getFieldSafe(spec3rdRes, 'pngSputter'));
    
    png_stack_spu  = getFileIfExists(getFieldSafe(evtStacksRes,'pngSputter'));
    
    png_csdr_spu   = getFileIfExists(getFieldSafe(csdRasterRes,'pngSputter'));
    png_timeavg_spu= getFileIfExists(getFieldSafe(csdTimeAvgRes,'pngSputter'));

    fprintf('  Gathering SPUTTER files:\n');
    fprintf('    LEFT col 1 (VoltRaster): %s\n',   tern(png_volt_spu=="","",png_volt_spu));
    fprintf('    LEFT col 2 (CSDSlices): %s\n',    tern(png_slice_spu=="","",png_slice_spu));
    fprintf('    LEFT col 3 (Theta): %s\n',        tern(png_theta_spu=="","",png_theta_spu));
    fprintf('    LEFT col 4 (Spectrogram): %s\n',  tern(png_spec_spu=="","",png_spec_spu));
    fprintf('    CENTER col (EvtStacks): %s\n',    tern(png_stack_spu=="","",png_stack_spu));
    fprintf('    RIGHT col 1 (CSDRaster): %s\n',   tern(png_csdr_spu=="","",png_csdr_spu));
    fprintf('    RIGHT col 2 (CSDTimeAvg): %s\n',  tern(png_timeavg_spu=="","",png_timeavg_spu));
    
    colLeft_SPU = stackVerticalHiRes({png_volt_spu, png_slice_spu, png_theta_spu, png_spec_spu}, 6);
    colCtr_SPU  = png_stack_spu;
    colRight_SPU= stackVerticalHiRes({png_csdr_spu, png_timeavg_spu}, 6);

    cols_SPU = filterNonEmpty({colLeft_SPU, colCtr_SPU, colRight_SPU});
    if isempty(cols_SPU)
        fprintf('  [8] FAILED: No valid SPUTTER PNGs were found to assemble.\n');
        warning('Pipeline:NoSputterPNGs', 'No SPUTTER images found; SPUTTER compact montage not created.');
    else
        fprintf('  [8] Assembling %d columns...\n', numel(cols_SPU));
        composeColumnsHiRes(cols_SPU, triptychSPUTTER, 10);
        fprintf('  [8] SUCCESS: Master SPUTTER compact montage saved: %s\n', triptychSPUTTER);
    end
catch ME
    fprintf('  [8] FAILED: Assembly of SPUTTER triptych.\n');
    warning(ME.identifier, 'Failed to build SPUTTER compact montage: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

% ---------- Merge available stats into a single CSV ----------
fprintf('===== [9] MERGING Stats CSV =====\n');
fprintf('  Target path: %s\n', masterCSV);
T = table();
csv_stacks = getFileIfExists(getFieldSafe(evtStacksRes, 'statsCSV'));
csv_volt   = getFileIfExists(getFieldSafe(voltRasterRes, 'statsCSV'));
csv_csdr   = getFileIfExists(getFieldSafe(csdRasterRes, 'statsCSV'));
csv_slice  = getFileIfExists(getFieldSafe(csdSlicesRes, 'statsCSV'));
csv_timeavg= getFileIfExists(getFieldSafe(csdTimeAvgRes, 'statsCSV'));

fprintf('  Found CSVs to merge:\n');
fprintf('    -> EventStacks: %s\n',     tern(csv_stacks=="","",csv_stacks));
fprintf('    -> VoltageRaster: %s\n',   tern(csv_volt=="","",csv_volt));
fprintf('    -> CSDRaster: %s\n',       tern(csv_csdr=="","",csv_csdr));
fprintf('    -> CSDCenterSlices: %s\n', tern(csv_slice=="","",csv_slice));
fprintf('    -> CSDTimeAvg: %s\n',      tern(csv_timeavg=="","",csv_timeavg));

T = tryAddCSV(T, evtStacksRes,  'EventStacks');
T = tryAddCSV(T, voltRasterRes, 'VoltageRaster');
T = tryAddCSV(T, csdRasterRes,  'CSDRaster');
T = tryAddCSV(T, csdSlicesRes,  'CSDCenterSlices');
T = tryAddCSV(T, csdTimeAvgRes, 'CSDTimeAvg');
% (Spectrogram block has no CSV)
try
    if isempty(T)
        fprintf('  [9] No stats CSVs found. Creating an EMPTY stats file.\n');
        T = table(string(datetime('now')), "EMPTY", 'VariableNames', {'GeneratedAt','Note'});
    else
        fprintf('  [9] Merged %d rows of stats.\n', height(T));
    end
    writetable(T, masterCSV);
    fprintf('  [9] SUCCESS: Master stats CSV saved: %s\n', masterCSV);
catch ME
    fprintf('  [9] FAILED: Writing master stats CSV.\n');
    warning(ME.identifier, 'Failed writing master stats CSV: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

% ---------- Round up PDFs (non-Sputter) ----------
fprintf('===== [10] COLLECTING PDFs =====\n');
try
    fprintf('\n');
    collectPdfs(masterOutDir, ...
        thetaRes, evtStacksRes, voltRasterRes, csdRasterRes, ...
        csdSlicesRes, csdTimeAvgRes, spec3rdRes);
    fprintf('  [10] SUCCESS: PDF collection complete.\n');
catch ME
    fprintf('  [10] FAILED: PDF collection.\n');
    warning(ME.identifier, 'Failed to round up PDF files: %s', ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
fprintf('--------------------------------------------------------\n');

fprintf('\n========================================================\n');
fprintf('===== Pipeline_Main COMPLETE =====\n');
fprintf('========================================================\n');

end

% ================= helpers (I/O-safe, native-res composition) ================

function s = tern(cond, a, b)
    % Helper for conditional printing
    if cond, s = a; else, s = b; end
end

function v = getFieldSafe(S, fieldName)
if ~(isstruct(S) && isfield(S, fieldName))
    v = "";
else
    v = string(S.(fieldName));
end
end

function p = getFileIfExists(s)
p = "";
if strlength(s) > 0
    c = char(s);
    if isfile(c), p = c; end
end
end

function C = filterNonEmpty(Cin)
C = {};
for i = 1:numel(Cin)
    if ~isempty(Cin{i})
        C{end+1} = Cin{i}; %#ok<AGROW>
    end
end
end

function outPath = stackVerticalHiRes(pngList, sep)
% Returns a path to a temp PNG that is a vertical stack of the inputs at native res.
% If zero or one valid png in list, returns [] or that single path as-is.
pngList = pngList(~cellfun(@isempty, pngList));
if isempty(pngList)
    outPath = [];
    return;
elseif numel(pngList) == 1
    outPath = pngList{1};
    return;
end

% read
imgs = cell(numel(pngList),1);
widths = zeros(numel(pngList),1);
heights= zeros(numel(pngList),1);
try
    for i = 1:numel(pngList)
        imgs{i} = imread(pngList{i});
        [h,w,~] = size(imgs{i});
        widths(i)  = w;
        heights(i) = h;
    end
catch ME
    fprintf('      ERROR in stackVerticalHiRes (reading images): %s\n', ME.message);
    outPath = [];
    return;
end

Wmax = max(widths);

% prep white canvas
cls = class(imgs{1});
switch cls
    case {'uint8'},  whiteVal = uint8(255);
    case {'uint16'}, whiteVal = uint16(65535);
    case {'double'}, whiteVal = 1;
    case {'single'}, whiteVal = single(1);
    otherwise, error('Unsupported image class: %s', cls);
end
totalH = sum(heights) + sep*(numel(imgs)-1);
if size(imgs{1},3) == 1
    out = repmat(whiteVal, [totalH, Wmax, 1]);
else
    out = repmat(reshape(whiteVal,1,1,[]), [totalH, Wmax, size(imgs{1},3)]);
end

% paste
y = 1;
for i = 1:numel(imgs)
    I = imgs{i}; [h,w,c] = size(I);
    out(y:y+h-1, 1:w, 1:c) = I;
    y = y + h;
    if i < numel(imgs), out(y:y+sep-1, :, :) = whiteVal; y = y + sep; end
end

% save to a temp in master output dir sibling
try
    tmpDir = tempname; mkdir(tmpDir);
    outPath = fullfile(tmpDir, sprintf('colV_%s.png', char(java.util.UUID.randomUUID)));
    imwrite(out, outPath);
catch ME
    fprintf('      ERROR in stackVerticalHiRes (saving temp file): %s\n', ME.message);
    outPath = [];
end
end

function composeColumnsHiRes(columnImgs, outPath, colSep)
% Compose LEFT→RIGHT at native res, no resampling.
assert(~isempty(columnImgs), 'composeColumnsHiRes: no columns to compose.');

% read columns
cols = cell(numel(columnImgs),1);
cw   = zeros(numel(columnImgs),1);
ch   = zeros(numel(columnImgs),1);
try
    for i = 1:numel(columnImgs)
        cols{i} = imread(columnImgs{i});
        [h,w,~] = size(cols{i});
        cw(i) = w; ch(i) = h;
    end
catch ME
    fprintf('      ERROR in composeColumnsHiRes (reading images): %s\n', ME.message);
    return;
end

Hmax = max(ch);
Wsum = sum(cw) + colSep*(numel(cols)-1);

% white canvas of proper class
cls = class(cols{1});
switch cls
    case {'uint8'},  whiteVal = uint8(255);
    case {'uint16'}, whiteVal = uint16(65535);
    case {'double'}, whiteVal = 1;
    case {'single'}, whiteVal = single(1);
    otherwise, error('Unsupported image class: %s', cls);
end
if size(cols{1},3) == 1
    out = repmat(whiteVal, [Hmax, Wsum, 1]);
else
    out = repmat(reshape(whiteVal,1,1,[]), [Hmax, Wsum, size(cols{1},3)]);
end

% paste columns top-aligned
x = 1;
for i = 1:numel(cols)
    I = cols{i}; [h,w,c] = size(I);
    out(1:h, x:x+w-1, 1:c) = I;
    x = x + w;
    if i < numel(cols), out(:, x:x+colSep-1, :) = whiteVal; x = x + colSep; end
end

try
    imwrite(out, outPath);
catch ME
    fprintf('      ERROR in composeColumnsHiRes (saving final triptych): %s\n', ME.message);
end
end

function T = tryAddCSV(T, res, tag)
try
    csvPath = getFileIfExists(getFieldSafe(res, 'statsCSV'));
    if csvPath ~= ""
        C = readtable(csvPath);
        if ~ismember('source', C.Properties.VariableNames)
            C.source = repmat(string(tag), height(C), 1);
        else
            C.source = string(C.source);
        end
        T = vertcatSafe(T, C);
        fprintf('    -> Successfully added %s\n', csvPath);
    else
        fprintf('    -> No CSV found for %s.\n', tag);
    end
catch ME
    warning(ME.identifier, 'Failed to merge stats from %s: %s', tag, ME.message);
    fprintf('      -> Error details: %s (Identifier: %s)\n', ME.message, ME.identifier);
end
end

function T = vertcatSafe(A, B)
if isempty(A), T = B; return; end
if isempty(B), T = A; return; end
allVars = union(A.Properties.VariableNames, B.Properties.VariableNames, 'stable');
A = addMissingVars(A, allVars);
B = addMissingVars(B, allVars);
T = [A; B]; %#ok<AGROW>
end

function T = addMissingVars(T, allVars)
missing = setdiff(allVars, T.Properties.VariableNames, 'stable');
for k = 1:numel(missing)
    T.(missing{k}) = missingDefault();
end
T = T(:, allVars);
end

function x = missingDefault()
x = missing;
end

% --- NEW ROBUST PDF COLLECTION FUNCTION ---
function collectPdfs(masterOutDir, varargin)
% Gathers all "SOLID" and global PDFs from the results structs
% and copies them into a single "PDF_OUT" folder.

pdfOutDir = fullfile(masterOutDir, 'PDF_OUT');
if ~exist(pdfOutDir, 'dir'), mkdir(pdfOutDir); end

fprintf('  [10] Rounding up non-Sputter PDFs into: %s\n', pdfOutDir);
collectedPaths = {};

% Loop through all result structs passed in
for i = 1:numel(varargin)
    res = varargin{i};
    if ~isstruct(res), continue; end
    
    fnames = fieldnames(res);
    
    % Find fields that contain 'pdf'
    pdfFields = fnames(contains(fnames, 'pdf', 'IgnoreCase', true));
    
    for k = 1:numel(pdfFields)
        fname = pdfFields{k};
        pdfPathStr = getFieldSafe(res, fname);
        
        if strlength(pdfPathStr) == 0
            continue; % Skip empty paths
        end
        
        % --- THIS IS THE FIX ---
        % Exclude if EITHER the field name OR the path itself contains "Sputter"
        isSputterField = contains(fname, 'Sputter', 'IgnoreCase', true);
        isSputterPath  = contains(pdfPathStr, 'Sputter', 'IgnoreCase', true);
        
        if ~isSputterField && ~isSputterPath
            % This is a "Solid" or "Global" field and path
            collectedPaths{end+1} = char(pdfPathStr); %#ok<AGROW>
        end
        % --- END FIX ---
    end
end

% Use existing helpers to get a clean list of files that exist
finalPdfList = filterNonEmpty(collectedPaths);
finalPdfList = cellfun(@getFileIfExists, finalPdfList, 'UniformOutput', false);
finalPdfList = filterNonEmpty(finalPdfList);
finalPdfList = unique(finalPdfList, 'stable'); % Avoid duplicates (e.g., from thetaRes)

if isempty(finalPdfList)
    fprintf('    -> No non-Sputter PDFs found to collect.\n');
    return;
end

% Copy them over
nCopied = 0;
fprintf('    -> Found %d unique non-Sputter PDFs to copy:\n', numel(finalPdfList));
for i = 1:numel(finalPdfList)
    try
        [~, fname, fext] = fileparts(finalPdfList{i});
        dest = fullfile(pdfOutDir, [fname, fext]);
        copyfile(finalPdfList{i}, dest);
        fprintf('      -> Copied: %s\n', [fname, fext]);
        nCopied = nCopied + 1;
    catch ME
        warning('collectPdfs:copyFailed', 'Failed to copy %s: %s', finalPdfList{i}, ME.message);
    end
end
fprintf('    -> Successfully copied %d PDF files.\n', nCopied);
end