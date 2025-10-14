function vacc_global_threshold_v5(recDir, prc, sfx, llw)
% V5 — GLOBAL LL THRESHOLD (streamed, exact percentile; identical to full-matrix)
% Saves: recDir/global_ll_threshold.mat  with fields:
%   threshold, prc, sfx, llw, W, nLL, filesUsed

if nargin<2||isempty(prc), prc=99.5; end
if nargin<3||isempty(sfx), sfx=30000; end
if nargin<4||isempty(llw), llw=0.04; end
W = max(2, round(sfx*llw));

fprintf('\n=== GLOBAL LL THRESHOLD (v5) ===\nDir: %s\n', recDir);
fprintf('Params: sfx=%d Hz | llw=%.3f s | W=%d | prc=%.2f\n', sfx, llw, W, prc);

% 1) even-numbered CSC files
files = dir(fullfile(recDir,'CSC*.ncs'));
if isempty(files), error('No CSC*.ncs in %s', recDir); end
nums = cellfun(@(s) sscanf(s,'CSC%d.ncs'), {files.name});
keep = mod(nums,2)==0 & ~isnan(nums);
files = files(keep); nums = nums(keep);
[~,ix]=sort(nums); files=files(ix); nums=nums(ix);
if isempty(files), error('No even-numbered CSC files.'); end
fprintf('Using even channels: %s\n', mat2str(nums));

% 2) stream LL -> temp file
tmp = [tempname,'.bin']; fid=fopen(tmp,'w'); assert(fid>0);
nLL = uint64(0); vmin=+inf; vmax=-inf;
for k=1:numel(files)
  fn = fullfile(files(k).folder, files(k).name);
  fprintf('  [%2d/%2d] %s ... ', k, numel(files), files(k).name);
  samples = Nlx2MatCSC(fn,[0 0 0 0 1],0,1,[]);
  x = single(-samples(:)); L = numel(x);
  fprintf('(%d samp)\n', L);
  if L < W, continue; end

  curLL = 0;
  for i=1:W-1, curLL = curLL + abs(x(i+1)-x(i)); end
  fwrite(fid, single(curLL), 'single'); nLL=nLL+1;
  vmin=min(vmin,double(curLL)); vmax=max(vmax,double(curLL));
  for t=W+1:L
    curLL = curLL - abs(x(t-W+1)-x(t-W)) + abs(x(t)-x(t-1));
    fwrite(fid, single(curLL), 'single'); nLL=nLL+1;
    if curLL<vmin, vmin=double(curLL); end
    if curLL>vmax, vmax=double(curLL); end
  end
end
fclose(fid);
fprintf('LL windows: %s | range [%.4g, %.4g]\n', string(nLL), vmin, vmax);

% 3) exact percentile
if nLL==0, threshold = NaN;
else, threshold = exact_percentile_from_disk(tmp, nLL, prc, vmin, vmax);
end
if exist(tmp,'file'), try, delete(tmp); end, end

filesUsed = arrayfun(@(f) fullfile(f.folder,f.name), files, 'uni',0);
save(fullfile(recDir,'global_ll_threshold.mat'), ...
     'threshold','prc','sfx','llw','W','nLL','filesUsed');
fprintf('Global LL threshold (%.2f%%): %.6g  -> saved.\n', prc, threshold);

end

% ---------- helper ----------
function v = exact_percentile_from_disk(binPath, N, prc, vmin, vmax)
k = max(1, min(double(N), round(prc/100 * double(N))));
lo = vmin; hi = vmax; maxBin=65536; chunk=5e6; iter=1;
while true
  if ~isfinite(lo)||~isfinite(hi)||lo==hi, v=lo; return; end
  nb = min(maxBin, max(256, ceil(sqrt(double(N)))));
  edges = linspace(lo, hi, nb+1); cnt = zeros(1,nb);

  fid=fopen(binPath,'r'); assert(fid>0);
  while true
    buf=fread(fid,chunk,'single=>double'); if isempty(buf), break; end
    cnt = cnt + histcounts(buf, edges);
  end
  fclose(fid);

  csum=cumsum(cnt); b=find(csum>=k,1,'first');
  if isempty(b), v=hi; return; end
  left=(b>1)*csum(b-1); need=k-left;
  binLo=edges(b); binHi=edges(b+1);
  if binHi==binLo, v=binLo; return; end

  pool=zeros(0,1);
  fid=fopen(binPath,'r'); assert(fid>0);
  while true
    buf=fread(fid,chunk,'single=>double'); if isempty(buf), break; end
    mask=(buf>=binLo & buf<binHi) | (binHi==hi & buf==hi);
    if any(mask), pool=[pool; buf(mask)]; %#ok<AGROW>
    end
  end
  fclose(fid);

  if numel(pool)<=2e7
    pool=sort(pool); need=max(1,min(need,numel(pool))); v=pool(need); return;
  else
    lo=binLo; hi=binHi; iter=iter+1;
  end
end
end
