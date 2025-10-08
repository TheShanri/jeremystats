% 1) Build a global (across channels) above-threshold mask over time
a = nansum(Li, 1) > 0;          % At each time point, TRUE if ANY channel is above threshold (channel-wise OR)

% 2) Find event onsets/offsets on that global mask
a = diff(a);                    % Transitions: +1 means rising edge (event starts), -1 means falling edge (event ends)
eON  = find(a == 1) + 1;        % Global event start sample indices (corrected by +1 due to diff)
eOFF = find(a == -1);           % Global event end sample indices

% 3) Fix boundary conditions if needed
if eOFF(1) < eON(1); eON  = [1 eON];             end  % If an event appears to start before data, force start at sample 1
if length(eOFF) < length(eON); eOFF = [eOFF length(a)]; end  % If last event never closed, force end at last sample
if length(eOFF) ~= length(eON); error('start and end mismatch'); end  % Sanity check: starts and ends must pair

% 4) Store global event intervals (same for all channels)
ets(:, [1 2]) = [eON(:) eOFF(:)]; % Each row is [on off] for a global event spanning ANY channel

% 5) For each global event, mark which channels participated
ech = false(size(ets,1), size(Li,1));           % Preallocate: rows=events, cols=channels
for i = 1:size(ets,1)
  ech(i,:) = logical(nansum(Li(:, ets(i,1):ets(i,2)), 2)); 
  % Sum Li over time within this event for EACH channel.
  % If a channel is ever above threshold in the event window -> TRUE for that channel.
end

% 6) Merge events that are close in time and combine channel involvement
s = size(ets,1); indx = false(s,1);
for i = 1:s-1
  if (ets(i+1,1) - ets(i,2)) < sfx * .3          % If next event starts <300 ms after current one
    ets(i+1,1) = ets(i,1);                       % Merge by extending the next event’s start back to current start
    ech(i+1,:) = logical(sum(ech(i:i+1,:), 1));  % Channel-wise OR: any channel in either event counts as involved
    indx(i) = true;                               % Mark current row for removal (since merged into i+1)
  end
end
ets(indx,:) = [];  ech(indx,:) = [];             % Drop merged-into rows; keep the combined event rows
