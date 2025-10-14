function [ets,ech]=LLspikedetector_fixedthr(d,sfx,llw,thr,badch)
% LLspikedetector_fixedthr — IDENTICAL logic to original, but uses fixed thr
% Inputs:
%   d   : [ch x time] or vector
%   sfx : Hz
%   llw : sec (e.g., 0.04)
%   thr : numeric global LL threshold (scalar)
%   badch (opt): logical 1xC bad-channel mask

if nargin<3||isempty(llw), llw=.04; end
if nargin<4||isempty(thr), error('Pass numeric thr'); end
if ndims(d)>2, error('d must be vector or 2-D matrix'); end
if size(d,1)>size(d,2), d=d'; end
if nargin<5||isempty(badch), badch=false(1,size(d,1)); end

% 1) line-length
numsamples = round(llw*sfx);
if any(size(d)==1)
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

% 2) thresholding → events by global any-channel
Li = L>thr;
a  = nansum(Li,1)>0;
a  = diff(a);
eON  = find(a==1)+1;
eOFF = find(a==-1);
if ~isempty(eON) && ~isempty(eOFF)
  if eOFF(1)<eON(1), eON=[1 eON]; end
  if numel(eOFF)<numel(eON), eOFF=[eOFF length(a)]; end
end
if isempty(eON) || isempty(eOFF)
  ets=zeros(0,2); ech=false(0,size(Li,1)); return
end
if numel(eOFF)~=numel(eON), error('start/end mismatch'); end
ets = [eON(:) eOFF(:)];

% channel participation
ech = false(size(ets,1), size(Li,1));
for i=1:size(ets,1)
  ech(i,:)=logical(nansum(Li(:,ets(i,1):ets(i,2)),2));
end

% 3) post-processing: center, badch pruning, merge<300ms, min 25ms
ets = round(ets + (sfx*llw)/2);
ech(:,badch)=0;
idx = sum(ech,2)<1; ets(idx,:)=[]; ech(idx,:)=[];

% merge consecutive events if gap < 300ms
if ~isempty(ets)
  s=size(ets,1); toDel=false(s,1);
  for i=1:s-1
    if (ets(i+1,1)-ets(i,2)) < round(0.3*sfx)
      ets(i+1,1)=ets(i,1);
      ech(i+1,:)=logical(ech(i+1,:) | ech(i,:));
      toDel(i)=true;
    end
  end
  ets(toDel,:)=[]; ech(toDel,:)=[];
end

% drop events shorter than 25ms
if ~isempty(ets)
  tooShort = (ets(:,2)-ets(:,1)) < round(0.025*sfx);
  ets(tooShort,:)=[]; ech(tooShort,:)=[];
end
end
