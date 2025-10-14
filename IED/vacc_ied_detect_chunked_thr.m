function vacc_ied_detect_chunked_thr(globalThr)
% Chunked LLspikedetector runner (fixed global threshold) — IDENTICAL results
% Saves: ets.mat, ech.mat, and events_summary.csv next to this script.

if nargin<1||isempty(globalThr), error('Pass numeric globalThr.'); end
tic;
scriptDir = fileparts(mfilename('fullpath'));
addpath(scriptDir);
addpath("C:\Users\Z390\Desktop\jeremystats\IED\reqsPath");

% --- data discovery (even-numbered CSC*.ncs) ---
dataRoot = "D:\PTEN\PTEN\M13_pten\HF4s2aug1\2023-08-01_12-11-26";
files = dir(fullfile(dataRoot,'CSC*.ncs'));
if isempty(files), error('No .ncs in %s', dataRoot); end
nums = cellfun(@(s) sscanf(s,'CSC%d.ncs'), {files.name});
keep = mod(nums,2)==0 & ~isnan(nums);
files = files(keep); nums=nums(keep);
[nums,ix]=sort(nums,'ascend'); files=files(ix);
if isempty(files), error('No even-numbered CSC files.'); end
fprintf('[discovery] channels(even): %s\n', mat2str(nums));

% --- params ---
sfx = 30000; llw = 0.04; W = max(2, round(sfx*llw));
CHUNK_S = 60; mergeSmp = round(0.300*sfx);
ovlSamp = W + mergeSmp; chunkSamp = CHUNK_S*sfx;
fprintf('[params] sfx=%d | llw=%.3fs | W=%d | chunk=%ds | overlap=%d\n', ...
  sfx,llw,W,CHUNK_S,ovlSamp);

% --- load channels (row singles) ---
S = cell(1,numel(files));
for k=1:numel(files)
  fn=fullfile(files(k).folder, files(k).name);
  samples = Nlx2MatCSC(fn,[0 0 0 0 1],0,1,[]);
  S{k} = single(-reshape(samples,1,[]));
end
nChan=numel(S); T=min(cellfun(@numel,S));
nChunks = ceil(T/chunkSamp);
fprintf('[sizes] channels=%d | common length=%d (%.2f min) | chunks=%d\n', ...
  nChan, T, T/sfx/60, nChunks);

% --- chunked detection ---
ets_all = zeros(0,2);
ech_all = false(0,nChan);

startIdx=1; chunkIdx=0;
while startIdx<=T
  chunkIdx=chunkIdx+1;
  interiorStart = startIdx;
  interiorEnd   = min(startIdx+chunkSamp-1, T);
  chunkStart = max(1, interiorStart-ovlSamp);
  chunkEnd   = min(interiorEnd+ovlSamp, T);

  d_chunk = zeros(nChan, chunkEnd-chunkStart+1, 'single');
  for ch=1:nChan, d_chunk(ch,:)=S{ch}(chunkStart:chunkEnd); end

  % detect with fixed threshold
  [etsC,echC] = LLspikedetector_fixedthr(d_chunk, sfx, llw, globalThr);

  % keep only events whose centered onset lies INSIDE interior
  if ~isempty(etsC)
    intLo = interiorStart - chunkStart + 1;
    intHi = interiorEnd   - chunkStart + 1;
    keep = (etsC(:,1)>=intLo) & (etsC(:,1)<=intHi);
    etsC = etsC(keep,:); echC=echC(keep,:);
    if ~isempty(etsC)
      etsC = etsC + (chunkStart-1); % shift to global
      ets_all = [ets_all; etsC];    %#ok<AGROW>
      ech_all = [ech_all; echC];    %#ok<AGROW>
    end
  end

  startIdx = interiorEnd+1;
end

% --- FINAL GLOBAL MERGE across all chunks (ensures identity)
[ets_all,ech_all] = merge_events_global(ets_all, ech_all, sfx);

% --- save .mat
ets=ets_all; ech=ech_all; %#ok<NASGU>
save(fullfile(scriptDir,'ets.mat'),'ets');
save(fullfile(scriptDir,'ech.mat'),'ech');

% --- write CSV summary (sample/time + channels list)
csvPath = fullfile(scriptDir,'events_summary.csv');
write_events_csv(csvPath, ets_all, ech_all, sfx, nums);

fprintf('[save] ets.mat, ech.mat, %s\n', csvPath);
fprintf('[done] events: %d | elapsed: %.1fs\n', size(ets_all,1), toc);
end

% ===== helpers =====

function [etsM, echM] = merge_events_global(ets, ech, sfx)
% Sort, then merge sequential events if gap < 300 ms; OR the channel flags
if isempty(ets), etsM=ets; echM=ech; return; end
[~,ord]=sort(ets(:,1)); ets=ets(ord,:); ech=ech(ord,:);
gapMax = round(0.300*sfx);

etsM = ets(1,:); echM = ech(1,:);
for i=2:size(ets,1)
  if (ets(i,1) - etsM(end,2)) < gapMax
    % merge into previous
    etsM(end,2) = max(etsM(end,2), ets(i,2));
    echM(end,:) = echM(end,:) | ech(i,:);
  else
    etsM = [etsM; ets(i,:)];          %#ok<AGROW>
    echM = [echM; ech(i,:)];          %#ok<AGROW>
  end
end

% apply min duration 25 ms (same as detector)
minSamp = round(0.025*sfx);
keep = (etsM(:,2)-etsM(:,1)) >= minSamp;
etsM = etsM(keep,:); echM = echM(keep,:);
end

function write_events_csv(csvPath, ets, ech, sfx, chanNums)
% CSV columns: sample_start, sample_end, time_start, time_end, channels
% channels column is a comma-separated list of channel numbers
fid = fopen(csvPath,'w'); assert(fid>0);
fprintf(fid,'sample_start,sample_end,time_start_s,time_end_s,channels\n');
for i=1:size(ets,1)
  ss = ets(i,1); ee = ets(i,2);
  ts = (ss-1)/sfx; te = (ee-1)/sfx;
  chIdx = find(ech(i,:));
  if nargin>=5 && ~isempty(chanNums)
    chList = sprintf('%d,', chanNums(1,numel(chanNums)>=numel(ech(i,:)) * chIdx) ); %#ok<NASGU>
    % Simpler / safe:
    chList = strjoin(string(chanNums(chIdx)), ',');
  else
    chList = strjoin(string(chIdx), ',');
  end
  fprintf(fid,'%d,%d,%.6f,%.6f,%s\n', ss, ee, ts, te, chList);
end
fclose(fid);
end
