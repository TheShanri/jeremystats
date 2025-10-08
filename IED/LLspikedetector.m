function [ets,ech]=LLspikedetector(d,sfx,llw,prc,badch)
%jon.kleen@ucsf.edu 2016-2023
% Transforms data into linelength then detects events (spikes) surpassing
% the designated percentile threshold. Note that this function assumes any 
% detections in any channel occurring simultaneously are involved in the 
% same spike event. 
% Based on Estellar et al 2001, DOI 10.1109/IEMBS.2001.1020545
%INPUTS
  % d: vector or matrix of ICEEG data and 
  % sfx: sampling frequency
  % llw: linelength window (in seconds) over which to calculate transform
  % prc: percentile to use as a threshold for detections
  % badch: logical index of bad channels (1=bad, 0=ok)
% OUTPUTS
  % ets: matrix of events (rows) and their on/off times (2 columns) in samples
  % ech: logical index of which channels are involved in each detection, 
%        thus having the same number of rows (spikes) as ets
  
%Example: [ets,ech]=LLspikedetector(d,512,.04,99.99)

if ~exist('llw','var')||isempty(llw); llw=.04; end %default linelength window for transform is 40ms
if ~exist('prc','var')||isempty(prc); prc=99.5; end %default percentile is 99.9%
if length(size(d))>2; error('Accepts only vector or 2-D matrix for data'); end
if size(d,1)>size(d,2); d=d'; end %flip if needed for loop (assumes longer dimension is time)
if ~exist('badch','var')||isempty(badch); badch=false(1,size(d,1)); end %default: all channels ok


%%  1. LINE-LENGTH TRANSFORM
numsamples=round(llw*sfx); % number of samples in the transform window
if any(size(d)==1)   %if d is a vector
  L=nan(1,length(d));
  for i=1:length(d)-numsamples
    L(i)=sum(abs(diff(d(i:i+numsamples-1))));
  end 
else                 
  L=nan(size(d));
  for i=1:size(d,2)-numsamples
  L(:,i)=sum(abs(diff(d(:,i:i+numsamples-1),1,2)),2);
  end
end


%%  2. DETECT EVENTS
Lvec=reshape(L,1,numel(L)); Lvec(isnan(Lvec))=[]; 
if ~iscell(prc); threshold=prctile(Lvec,prc); 
else; threshold=str2double(prc{1});
end
Li=L>threshold; 

% >>> CROSS-CHANNEL LOGIC STARTS HERE <<<
% THIS LINE SUMS ACROSS CHANNELS TO FIND ANY TIME POINT WHERE AT LEAST ONE CHANNEL IS ABOVE THRESHOLD
a=nansum(Li,1)>0;   
a=diff(a);
eON=find(a==1)+1; 
eOFF=find(a==-1);
  if eOFF(1)<eON(1); eON=[1 eON]; end 
  if length(eOFF)<length(eON); eOFF=[eOFF length(a)]; end 
  if length(eOFF)~=length(eON); error('start and end of events is not matching up, check your code'); end
ets(:,[1 2])=[eON(:) eOFF(:)];
% <<< CROSS-CHANNEL LOGIC ABOVE CREATES GLOBAL EVENT ON/OFF TIMES BASED ON ANY CHANNEL >>>

%Channel indexing for each event
ech=false(size(ets,1),size(Li,1));
for i=1:size(ets,1)
  % >>> CROSS-CHANNEL LOGIC: THIS SUM ACROSS CHANNELS DETERMINES WHICH CHANNELS WERE ACTIVE FOR EACH EVENT
  ech(i,:)=logical(nansum(Li(:,ets(i,1):ets(i,2)),2));  
end
% <<< CROSS-CHANNEL LOGIC ABOVE BUILDS THE CHANNEL PARTICIPATION MATRIX (ECH) >>>

%%  3. Additional checks/corrections
ets=round(ets+(sfx*llw)/2); 

ech(:,badch)=0; 
idx=sum(ech,2)<1;    ech(idx,:)=[];    ets(idx,:)=[]; clear idx

% >>> CROSS-CHANNEL LOGIC: MERGES EVENTS THAT OCCUR CLOSE IN TIME ACROSS CHANNELS AND COMBINES THEIR ECH FLAGS
s=size(ets,1); indx=false(s,1); 
for i=1:s-1
  if (ets(i+1,1)-ets(i,2))<sfx*.3
    ets(i+1,1)=ets(i,1); 
    ech(i+1,:)=logical(sum(ech(i:i+1,:),1));  % <<< CHANNEL UNION (OR) ACROSS MERGED EVENTS >>>
    indx(i)=true;
  end
end
ets(indx,:)=[];  ech(indx,:)=[]; 
% <<< CROSS-CHANNEL LOGIC ABOVE ENSURES OVERLAPPING OR NEARBY MULTI-CHANNEL EVENTS ARE MERGED TOGETHER >>>

minL=.025; 
tooshort=diff(ets,1,2)<(sfx*minL);
ets(tooshort,:)=[];  ech(tooshort,:)=[]; clear tooshort
% Tada
