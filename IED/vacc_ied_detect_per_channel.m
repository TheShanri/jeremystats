function vacc_ied_detect_per_channel()
  % Paths (adjust as you had)
  baseDir  = fileparts(mfilename('fullpath'));
  dataDir  = fullfile(baseDir, 'IED DATA');
  addpath(baseDir);
  addpath(fullfile("C:\Users\Z390\Desktop\jeremystats\IED\reqsPath"));

  recDir   = "D:\PTEN\PTEN\M13_pten\HF4s2aug1\2023-08-01_12-11-26";
  files    = dir(fullfile(recDir, 'CSC*.ncs'));
  if isempty(files), error('No .ncs files found in: %s', recDir); end

  % keep even-numbered CSC files
  names = {files.name};
  nums  = cellfun(@(s) sscanf(s,'CSC%d.ncs'), names);
  keep  = mod(nums,2)==0 & ~isnan(nums);
  files = files(keep);
  if isempty(files)
    error('No even-numbered CSC*.ncs files found in: %s', recDir);
  end

  % Fixed params
  sfx = 30000;   % Hz
  llw = 0.04;    % 40 ms
  prc = 99.9;    % percentile

  % --- 1) Run LLspikedetector one channel at a time ---
  ets_by_ch = cell(1, numel(files));
  for k = 1:numel(files)
    fn = fullfile(files(k).folder, files(k).name);
    % Samples only: [0 0 0 0 1], no header, Extract All (mode=1)
    samples = Nlx2MatCSC(fn, [0 0 0 0 1], 0, 1, []);
    s = single(-samples(:)');  % vectorize 512-by-N -> 1-by-T, invert polarity
    [ets_k, ~] = LLspikedetector(s, sfx, llw, prc);  % per-channel events
    % stash with channel index
    if ~isempty(ets_k)
      ets_by_ch{k} = [ets_k, repmat(k, size(ets_k,1), 1)]; % [on off ch]
    else
      ets_by_ch{k} = zeros(0,3,'like',s);                  % empty row set
    end
  end

  % If nothing detected anywhere, save empties and exit
  all_rows = cellfun(@(c) size(c,1), ets_by_ch);
  if ~any(all_rows)
    ets = zeros(0,2,'uint32');  %#ok<NASGU>
    ech = false(0, numel(files)); %#ok<NASGU>
    save(fullfile(dataDir,'ets.mat'),'ets');
    save(fullfile(dataDir,'ech.mat'),'ech');
    return
  end

  % --- 2) Union + merge events across channels (like original logic) ---
  A = vertcat(ets_by_ch{:});   % [on off ch], all channels
  A = sortrows(A, 1);          % sort by onset
  % Build union of intervals, merging overlaps and gaps < 300 ms
  gapSamps = round(sfx * 0.3);
  ets_comb = zeros(0,2,'like',A);  % combined [on off]
  cur_on = A(1,1); cur_off = A(1,2);
  for i = 2:size(A,1)
    on = A(i,1); off = A(i,2);
    if on <= cur_off + gapSamps
      if off > cur_off, cur_off = off; end  % extend
    else
      ets_comb(end+1,:) = [cur_on, cur_off]; %#ok<AGROW>
      cur_on = on; cur_off = off;
    end
  end
  ets_comb(end+1,:) = [cur_on, cur_off];

  % --- 3) Build ech: mark channels participating in each combined event ---
  nCh  = numel(files);
  ech  = false(size(ets_comb,1), nCh);
  % Pre-split intervals by channel for quick overlap checks
  ch_intervals = cell(1,nCh);
  for k = 1:nCh
    if ~isempty(ets_by_ch{k})
      ch_intervals{k} = ets_by_ch{k}(:,1:2); % [on off]
    else
      ch_intervals{k} = zeros(0,2,'like',A);
    end
  end
  % Overlap test: [a1,a2] and [b1,b2] overlap if a1<=b2 && b1<=a2
  for i = 1:size(ets_comb,1)
    on = ets_comb(i,1); off = ets_comb(i,2);
    for k = 1:nCh
      iv = ch_intervals{k};
      if ~isempty(iv)
        % any interval overlapping this combined event?
        hit = any(iv(:,1) <= off & on <= iv(:,2));
        ech(i,k) = hit;
      end
    end
  end

  % Optional: enforce minimum duration (25 ms) like LLspikedetector
  minL = round(sfx * 0.025);
  keep = (ets_comb(:,2) - ets_comb(:,1)) >= minL;
  ets  = ets_comb(keep,:); %#ok<NASGU>
  ech  = ech(keep,:);      %#ok<NASGU>

  % --- 4) Save outputs ---
  save(fullfile(dataDir, 'ets.mat'), 'ets');
  save(fullfile(dataDir, 'ech.mat'), 'ech');
end
