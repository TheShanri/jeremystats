function vacc_ied_detect_per_channel()
  %----------------------------------------------------------
  % VACC IED DETECTOR — memory-safe per-channel implementation
  %----------------------------------------------------------
  % Runs LLspikedetector() channel-by-channel to avoid
  % massive memory allocations from full 32×long recordings.
  %----------------------------------------------------------

  fprintf('\n=== VACC IED DETECT — Per-Channel Mode ===\n');

  %----------------------------------------------------------
  % 1) Setup paths and find CSC files
  %----------------------------------------------------------
  baseDir  = fileparts(mfilename('fullpath'));
  dataDir  = fullfile(baseDir, 'IED DATA');
  addpath(baseDir);
  addpath(fullfile("C:\Users\Z390\Desktop\jeremystats\IED\reqsPath"));

  recDir = "D:\PTEN\PTEN\M13_pten\HF4s2aug1\2023-08-01_12-11-26";
  fprintf('> Scanning directory: %s\n', recDir);

  files = dir(fullfile(recDir, 'CSC*.ncs'));
  if isempty(files)
    error('No .ncs files found in: %s', recDir);
  end

  % Keep even-numbered CSC files
  names = {files.name};
  nums  = cellfun(@(s) sscanf(s,'CSC%d.ncs'), names);
  keep  = mod(nums,2)==0 & ~isnan(nums);
  files = files(keep);
  if isempty(files)
    error('No even-numbered CSC*.ncs files found in: %s', recDir);
  end
  fprintf('> Found %d even CSC files.\n', numel(files));

  % Fixed params
  sfx = 30000; llw = 0.04; prc = 99.9;
  fprintf('> Params: %.0f Hz, LL window %.3fs, %.3f percentile.\n', sfx, llw, prc);

  %----------------------------------------------------------
  % 2) Run LLspikedetector one channel at a time
  %----------------------------------------------------------
  ets_by_ch = cell(1, numel(files));

  for k = 1:numel(files)
    fn = fullfile(files(k).folder, files(k).name);
    fprintf('\n[Channel %2d/%2d] Reading %s ...\n', k, numel(files), files(k).name);

    samples = Nlx2MatCSC(fn, [0 0 0 0 1], 0, 1, []);
    s = single(-samples(:)');   % flatten + invert polarity
    fprintf('   > Running LLspikedetector ... ');
    [ets_k, ~] = LLspikedetector(s, sfx, llw, prc);
    fprintf('done (%d events)\n', size(ets_k,1));

    if ~isempty(ets_k)
      ets_by_ch{k} = [ets_k, repmat(k, size(ets_k,1), 1)];
    else
      ets_by_ch{k} = zeros(0,3,'single');
    end
  end

  %----------------------------------------------------------
  % 3) Merge detections across channels
  %----------------------------------------------------------
  fprintf('\n> Combining detections across channels ...\n');
  all_rows = cellfun(@(c) size(c,1), ets_by_ch);
  if ~any(all_rows)
    fprintf('   No detections found. Saving empty outputs.\n');
    ets = zeros(0,2,'uint32'); ech = false(0,numel(files));
    save(fullfile(dataDir,'ets.mat'),'ets');
    save(fullfile(dataDir,'ech.mat'),'ech');
    fprintf('=== Finished: no events ===\n');
    return
  end

  A = vertcat(ets_by_ch{:});   % [on off ch]
  A = sortrows(A,1);

  fprintf('   > Merging overlapping/close events ...\n');
  gapSamps = round(sfx * 0.3);
  ets_comb = zeros(0,2,'like',A);
  cur_on = A(1,1); cur_off = A(1,2);
  for i = 2:size(A,1)
    on = A(i,1); off = A(i,2);
    if on <= cur_off + gapSamps
      if off > cur_off, cur_off = off; end
    else
      ets_comb(end+1,:) = [cur_on, cur_off]; %#ok<AGROW>
      cur_on = on; cur_off = off;
    end
  end
  ets_comb(end+1,:) = [cur_on, cur_off];
  fprintf('   > Total merged events: %d\n', size(ets_comb,1));

  %----------------------------------------------------------
  % 4) Build ech matrix
  %----------------------------------------------------------
  fprintf('> Building channel involvement matrix ...\n');
  nCh = numel(files);
  ech = false(size(ets_comb,1), nCh);
  ch_intervals = cell(1,nCh);
  for k = 1:nCh
    ch_intervals{k} = ets_by_ch{k}(:,1:2);
  end

  for i = 1:size(ets_comb,1)
    on = ets_comb(i,1); off = ets_comb(i,2);
    for k = 1:nCh
      iv = ch_intervals{k};
      if ~isempty(iv)
        hit = any(iv(:,1) <= off & on <= iv(:,2));
        ech(i,k) = hit;
      end
    end
    if mod(i,100)==0 || i==size(ets_comb,1)
      fprintf('   Processed %d/%d events...\n', i, size(ets_comb,1));
    end
  end

  %----------------------------------------------------------
  % 5) Minimum duration filter and save
  %----------------------------------------------------------
  fprintf('> Applying minimum duration filter ...\n');
  minL = round(sfx * 0.025);
  keep = (ets_comb(:,2) - ets_comb(:,1)) >= minL;
  ets = ets_comb(keep,:); %#ok<NASGU>
  ech = ech(keep,:);      %#ok<NASGU>
  fprintf('> Keeping %d events after duration filter.\n', size(ets,1));

  fprintf('> Saving outputs to %s\n', dataDir);
  save(fullfile(dataDir, 'ets.mat'), 'ets');
  save(fullfile(dataDir, 'ech.mat'), 'ech');

  fprintf('\n=== DONE: %d total events saved ===\n', size(ets,1));
end
