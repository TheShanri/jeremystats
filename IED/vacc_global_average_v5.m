function vacc_global_average_v5(recDir)
% V5 — GLOBAL LL AVERAGE (memory-lean, per-channel streaming)
% Usage:
%   vacc_global_average_v5("D:\PTEN\...\2023-08-01_12-11-26")
%
% Output:
%   Saves global_ll_mean.mat with fields:
%     meanLL, countLL, sfx, llw, nChannels, filesUsed

  % ---------- params ----------
  sfx = 30000;          % Hz
  llw = 0.04;           % sec (line-length window)
  W   = max(2, round(sfx*llw));  % samples per LL window (>=2)

  fprintf('\n=== GLOBAL LL AVERAGE (v5) ===\n');
  fprintf('Dir: %s\n', recDir);
  fprintf('Params: sfx=%d Hz, llw=%.3f s (W=%d)\n', sfx, llw, W);

  % ---------- find files (even CSC only, numeric order) ----------
  files = dir(fullfile(recDir, 'CSC*.ncs'));
  if isempty(files), error('No CSC*.ncs files in %s', recDir); end
  names = {files.name};
  nums  = cellfun(@(s) sscanf(s,'CSC%d.ncs'), names);
  keep  = mod(nums,2)==0 & ~isnan(nums);
  files = files(keep);  nums = nums(keep);
  [~,ix] = sort(nums,'ascend'); files = files(ix); nums = nums(ix);
  if isempty(files), error('No even-numbered CSC files.'); end
  fprintf('Channels used (even): %s\n', mat2str(nums));

  % ---------- running mean (Welford) ----------
  nLL   = uint64(0);
  meanLL = 0;

  for k = 1:numel(files)
    fn = fullfile(files(k).folder, files(k).name);
    fprintf('> [%2d/%2d] %s\n', k, numel(files), files(k).name);

    % Read one channel (Neuralynx): samples is [512 x Nrecords]
    samples = Nlx2MatCSC(fn, [0 0 0 0 1], 0, 1, []);
    x = single(-samples(:));   % flatten & invert polarity (as in your code)
    L = numel(x);
    if L < W, continue; end    % too short to form one LL window

    % ---- compute LL in a streaming way (no big arrays) ----
    % First window LL at index t=W uses x(1:W)
    % LL = sum_{i=1..W-1} |x(i+1) - x(i)|
    curLL = 0;
    for i = 1:W-1
      curLL = curLL + abs(x(i+1) - x(i));
    end
    % Update mean with first LL
    nLL = nLL + 1;
    meanLL = meanLL + (curLL - meanLL)/double(nLL);

    % Slide window: for each new sample at t>W
    % remove |x(t-W+1)-x(t-W)|, add |x(t)-x(t-1)|
    for t = W+1:L
      curLL = curLL ...
            - abs(x(t-W+1) - x(t-W)) ...
            + abs(x(t)     - x(t-1));
      nLL   = nLL + 1;
      meanLL = meanLL + (curLL - meanLL)/double(nLL);
    end
  end

  fprintf('\n=== RESULT ===\n');
  fprintf('Total LL windows: %s\n', string(nLL));
  fprintf('Global mean LL : %.6g\n', meanLL);

  % ---------- save ----------
  outPath = fullfile(recDir, 'global_ll_mean.mat');
  filesUsed = arrayfun(@(f) fullfile(f.folder,f.name), files, 'UniformOutput', false);
  save(outPath, 'meanLL','nLL','sfx','llw','W','filesUsed');
  fprintf('Saved: %s\n', outPath);
end
