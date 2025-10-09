function vacc_ied_detect_chunked3()
% Two-pass chunked runner that matches whole-file math:
%  A) Streaming exact global LL percentile (no giant arrays)
%  B) Chunked detection with fixed global threshold, overlap, final merge
%
% Verbose prints show progress for setup, pass A, pass B, and saving.

tStart = tic;
scriptDir = fileparts(mfilename('fullpath'));
fprintf('\n[vacc_v3] Script dir: %s\n', scriptDir);

% ---- paths ----
addpath(scriptDir);
addpath("C:\Users\Z390\Desktop\jeremystats\IED\reqsPath");
fprintf('[vacc_v3] Paths ready.\n');

% ---- data discovery (even-numbered CSC; numeric sort) ----
dataRoot = "D:\PTEN\PTEN\M13_pten\HF4s2aug1\2023-08-01_12-11-26";
files = dir(fullfile(dataRoot,'CSC*.ncs'));
if isempty(files), error('No .ncs in %s', dataRoot); end
nums = cellfun(@(s) sscanf(s,'CSC%d.ncs'), {files.name});
keep = mod(nums,2)==0 & ~isnan(nums);
files = files(keep); nums = nums(keep);
[nums,ord] = sort(nums,'ascend'); files = files(ord);
if isempty(files), error('No even-numbered CSC files in %s', dataRoot); end
fprintf('[vacc_v3] Channels: %s\n', mat2str(nums));

% ---- parameters ----
sfx       = 30000;      % Hz
llw       = 0.04;       % s
prcPct    = 99.9;       % global percentile
CHUNK_S   = 60;         % interior seconds per chunk
mergeSamp = round(0.3*sfx);
ovlSamp   = ceil(llw*sfx) + mergeSamp;   % cover LL and merge horizon
chunkSamp = CHUNK_S * sfx;
numsamples = round(llw*sfx);
fprintf('[vacc_v3] Params | sfx=%d, llw=%.3fs, prc=%.3f, chunk=%ds, overlap=%d samp\n', ...
        sfx, llw, prcPct, CHUNK_S, ovlSamp);

% ---- load channels into row vectors (single, inverted polarity) ----
nChan = numel(files);
S = cell(1,nChan);
for k=1:nChan
  fn = fullfile(files(k).folder, files(k).name);
  fprintf('[vacc_v3] Load  | %2d/%d %s ... ', k, nChan, files(k).name);
  blk = Nlx2MatCSC(fn,[0 0 0 0 1],0,1,[]); % 512xN blocks
  v = reshape(blk,1,[]);
  S{k} = single(-v);
  fprintf('OK (%d samples)\n', numel(v));
end
T = min(cellfun(@numel,S));      % analyze common duration
nChunks = ceil(T / chunkSamp);
fprintf('[vacc_v3] Size  | common length=%d samples (%.2f min), chunks=%d\n', T, T/sfx/60, nChunks);

% =========================
% PASS A: exact global LL percentile (streaming)
% =========================
fprintf('[vacc_v3] PASS A | Streaming global threshold (p=%.3f)...\n', prcPct);
[minLL, maxLL, N] = sweep_min_max_count(S, nChan, T, numsamples, chunkSamp, ovlSamp);
fprintf('[vacc_v3] PASS A | min=%.8g, max=%.8g, N=%d LL samples\n', minLL, maxLL, N);

k  = (prcPct/100)*(N-1) + 1;
j  = floor(k);
g  = k - j;
if j < 1, j = 1; end
if j >= N, j = N-1; g = 1; end
fprintf('[vacc_v3] PASS A | k=%.6f -> j=%d, g=%.6f (prctile linear interp)\n', k, j, g);

fprintf('[vacc_v3] PASS A | Searching v_j ...\n');
vj  = kth_order_value(j,   S, nChan, T, numsamples, chunkSamp, ovlSamp, minLL, maxLL);
fprintf('[vacc_v3] PASS A | Searching v_{j+1} ...\n');
vj1 = kth_order_value(j+1, S, nChan, T, numsamples, chunkSamp, ovlSamp, minLL, maxLL);

global_thr = vj + g * (vj1 - vj);
fixed_prc  = {num2str(global_thr)};
fprintf('[vacc_v3] PASS A | Global threshold = %.8g\n', global_thr);

% =========================
% PASS B: chunked detection with fixed threshold
% =========================
fprintf('[vacc_v3] PASS B | Detecting per chunk (overlap=%d samp)...\n', ovlSamp);
ets_all = zeros(0,2,'uint64'); 
ech_all = false(0,nChan);

startIdx = 1; cIdx = 0; totalKept = 0;
while startIdx <= T
  cIdx = cIdx + 1;
  interiorStart = startIdx;
  interiorEnd   = min(startIdx + chunkSamp - 1, T);
  chunkStart    = max(1, interiorStart - ovlSamp);
  chunkEnd      = min(interiorEnd + ovlSamp, T);

  secsLo = (interiorStart-1)/sfx; secsHi = (interiorEnd-1)/sfx;
  fprintf('[vacc_v3] Chunk  | %3d/%d samp [%d..%d], interior %.2f–%.2f s ... ', ...
          cIdx, nChunks, chunkStart, chunkEnd, secsLo, secsHi);

  % assemble chunk
  d = zeros(nChan, chunkEnd - chunkStart + 1, 'single');
  for ch=1:nChan, d(ch,:) = S{ch}(chunkStart:chunkEnd); end

  % detect with fixed global threshold
  [etsC, echC] = LLspikedetector3(d, sfx, llw, fixed_prc);

  % keep only events whose ONSET lies in the interior
  kept = 0;
  if ~isempty(etsC)
    intLo = interiorStart - chunkStart + 1;
    intHi = interiorEnd   - chunkStart + 1;
    mask  = (etsC(:,1) >= intLo) & (etsC(:,1) <= intHi);
    etsC = etsC(mask,:); echC = echC(mask,:);
    kept = size(etsC,1);
    if kept > 0
      etsC = uint64(etsC) + uint64(chunkStart - 1);
      ets_all = [ets_all; etsC]; %#ok<AGROW>
      ech_all = [ech_all; echC]; %#ok<AGROW>
    end
  end
  totalKept = totalKept + kept;
  fprintf('kept=%d | total=%d\n', kept, totalKept);

  startIdx = interiorEnd + 1;  % next 60s interior
end

fprintf('[vacc_v3] Merge  | Global merge of close events (<300ms)...\n');
[ets, ech] = merge_close_global(ets_all, ech_all, sfx);
fprintf('[vacc_v3] Result | final events=%d\n', size(ets,1));

save(fullfile(scriptDir,'ets.mat'),'ets');
save(fullfile(scriptDir,'ech.mat'),'ech');
fprintf('[vacc_v3] Saved  | ets.mat & ech.mat @ %s\n', scriptDir);
fprintf('[vacc_v3] Done   | elapsed %.2fs\n\n', toc(tStart));
end



% ===== helpers: streaming LL computations & exact order stats (with prints) =====

function [mn, mx, N] = sweep_min_max_count(S, nChan, T, numsamples, chunkSamp, ovlSamp)
mn = inf; mx = -inf; N = 0;
startIdx = 1; sweepIdx = 0;
while startIdx <= T
  sweepIdx = sweepIdx + 1;
  interiorStart = startIdx;
  interiorEnd   = min(startIdx + chunkSamp - 1, T);
  chunkStart    = max(1, interiorStart - ovlSamp);
  chunkEnd      = min(interiorEnd + ovlSamp, T);

  d = zeros(nChan, chunkEnd - chunkStart + 1, 'single');
  for ch=1:nChan, d(ch,:) = S{ch}(chunkStart:chunkEnd); end

  Llast = size(d,2)-numsamples;
  if Llast > 0
    % compute LL (channels x time)
    L = nan(nChan, Llast, 'single');
    for i=1:Llast
      L(:,i)=sum(abs(diff(d(:,i:i+numsamples-1),1,2)),2);
    end
    mn = min(mn, double(min(L(:))));
    mx = max(mx, double(max(L(:))));
    N  = N + nnz(~isnan(L));
  end

  if mod(sweepIdx,10)==0
    fprintf('[vacc_v3] PASS A | sweep chunk %d, N so far=%d\n', sweepIdx, N);
  end
  startIdx = interiorEnd + 1;
end
if ~isfinite(mn), mn = 0; end
if ~isfinite(mx), mx = 0; end
end

function v = kth_order_value(k, S, nChan, T, numsamples, chunkSamp, ovlSamp, lo, hi)
% Binary search for smallest v with count(LL <= v) >= k.
lo = double(lo); hi = double(hi);
iter = 0;
while lo < hi
  iter = iter + 1;
  mid = floor((lo + hi)/2);
  c = count_leq(mid, S, nChan, T, numsamples, chunkSamp, ovlSamp);
  if mod(iter,5)==0
    fprintf('[vacc_v3] PASS A | bs iter %2d: mid=%.8g, count=%d\n', iter, mid, c);
  end
  if c >= k
    hi = mid;
  else
    lo = mid + 1;
  end
end
v = lo;
fprintf('[vacc_v3] PASS A | bs done in %d iters -> v=%.8g\n', iter, v);
end

function c = count_leq(th, S, nChan, T, numsamples, chunkSamp, ovlSamp)
% Streaming count of LL values <= th (no storage of full LL).
c = 0;
startIdx = 1;
while startIdx <= T
  interiorStart = startIdx;
  interiorEnd   = min(startIdx + chunkSamp - 1, T);
  chunkStart    = max(1, interiorStart - ovlSamp);
  chunkEnd      = min(interiorEnd + ovlSamp, T);

  d = zeros(nChan, chunkEnd - chunkStart + 1, 'single');
  for ch=1:nChan, d(ch,:) = S{ch}(chunkStart:chunkEnd); end

  last = size(d,2)-numsamples;
  for i=1:last
    ll = sum(abs(diff(d(:,i:i+numsamples-1),1,2)),2); % nChan x 1
    c  = c + sum(ll <= th);
  end

  startIdx = interiorEnd + 1;
end
end

function [etsM, echM] = merge_close_global(ets, ech, sfx)
if isempty(ets), etsM=ets; echM=ech; return; end
[~,ord]=sort(ets(:,1),'ascend'); ets=ets(ord,:); ech=ech(ord,:);
s=size(ets,1); kill=false(s,1); gap=round(0.3*sfx);
for i=1:s-1
  if (ets(i+1,1)-ets(i,2)) < gap
    ets(i+1,1)=ets(i,1);
    ech(i+1,:)=logical(ech(i+1,:) | ech(i,:));
    kill(i)=true;
  end
end
etsM=ets(~kill,:); echM=ech(~kill,:);
end
