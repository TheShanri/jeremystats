% vacc_ied_detect.m — minimal, folder-based IED batch detector (single-precision)
% Runs on Batch_Processing/IED DATA and writes ets.mat / ech.mat back there.

function vacc_ied_detect()
  baseDir  = fileparts(mfilename('fullpath'));
  dataDir  = fullfile(baseDir, 'IED DATA');

  % Add required deps (LLspikedetector.m, Nlx2MatCSC.m/.mexa64)
  addpath(baseDir);
  addpath(fullfile(baseDir, 'reqsPath'));  % contains Nlx2MatCSC.* per repo layout

  files = dir(fullfile(dataDir, 'CSC*.ncs'));
  if isempty(files)
    error('No .ncs files found in: %s', dataDir);
  end

  % Keep only even-numbered CSC files
  names = {files.name};
  nums  = cellfun(@(s) sscanf(s,'CSC%d.ncs'), names);
  keep  = mod(nums,2)==0 & ~isnan(nums);
  files = files(keep);
  if isempty(files)
    error('No even-numbered CSC*.ncs files found in: %s', dataDir);
  end

  % Read all samples (ExtractMode 1, Samples only), invert polarity, collect as single
  S = cell(1, numel(files));
  for k = 1:numel(files)
    fn = fullfile(files(k).folder, files(k).name);
    % Samples only: FieldSelectionFlags=[0 0 0 0 1], no header, Extract All (mode 1), vec []
   samples = Nlx2MatCSC(fn, [0 0 0 0 1], 0, 1, []);
    s = reshape(samples, 1, []);        % 512-by-N → row
    s = single(-s);                     % invert default Neuralynx polarity, keep single (no doubles)
    S{k} = s; 
  end

  % Pad to rectangle
  maxlen = max(cellfun(@numel, S));
  d = zeros(numel(S), maxlen, 'single');
  for i = 1:numel(S)
    v = S{i};
    d(i, 1:numel(v)) = v;
  end

  % Fixed params per request
  sfx = 30000;         % Hz
  llw = 0.04;          % 40 ms window
  prc = 99.9;          % percentile threshold

  % Detect spikes (rows of ets are [on off] in samples; ech marks channels per event)
  [ets, ech] = LLspikedetector(d, sfx, llw, prc);           % algorithm ref. :contentReference[oaicite:2]{index=2} :contentReference[oaicite:3]{index=3} :contentReference[oaicite:4]{index=4}

  % Save outputs right next to data
  save(fullfile(dataDir, 'ets.mat'), 'ets');
  save(fullfile(dataDir, 'ech.mat'), 'ech');
end