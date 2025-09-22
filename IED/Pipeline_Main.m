function Pipeline_Main(inputFolder, dataMatPath)

% --- RUN MODULES (example: EventStacks) ---
evstacksOut = EventStacks_ampWidth_Avg_Pipeline( ...
    inputFolder, dataMatPath, ...
    'makeIndividualPNGs', false, ...   % let the master plot own rendering
    'returnTraces',       false );     % keep result light for now

% TODO: run the other modules here and collect their outputs:
% vrasOut  = VoltageRaster_EventsAvg_Pipeline(...);
% csdAvg   = CSDRaster_Avg_Pipeline(...);
% csd0     = CSD_CentersSlieces_Waveform_AvgGroups_Pipeline(...);
% csdTavg  = CSD_TimeAvg_Waveform_AvgGroups_Pipeline(...);

% -----------------------------------------------------------
% TABLES: group-level (scalars) + channel-level (per channel)
% -----------------------------------------------------------

% Group-level: one row per group with scalar stats
allStats = table('Size',[0 8], ...
    'VariableTypes', {'string','string','double','double','double','double','double','double'}, ...
    'VariableNames', {'Module','Group','NEvents','NChannels','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});

% Channel-level: one row per channel per group
allStatsByChannel = table('Size',[0 9], ...
    'VariableTypes', {'string','string','double','double','double','double','double','double','double'}, ...
    'VariableNames', {'Module','Group','ChannelIndex','CSC','NUsed','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});

% ---- collect stats from EventStacks (EXAMPLE) ----
[grpTbl, chTbl] = statsFrom_EventStacks(evstacksOut);
allStats         = [allStats; grpTbl];
allStatsByChannel= [allStatsByChannel; chTbl];

% TODO: append from other modules the same way:
% [grpTbl, chTbl] = statsFrom_VoltageRaster(vrasOut);            allStats = [allStats; grpTbl]; allStatsByChannel = [allStatsByChannel; chTbl];
% [grpTbl, chTbl] = statsFrom_CSDRasterAvg(csdAvg);              allStats = [allStats; grpTbl]; allStatsByChannel = [allStatsByChannel; chTbl];
% [grpTbl, chTbl] = statsFrom_CSD_CenterSlices(csd0);            allStats = [allStats; grpTbl]; allStatsByChannel = [allStatsByChannel; chTbl];
% [grpTbl, chTbl] = statsFrom_CSD_TimeAveraged(csdTavg);         allStats = [allStats; grpTbl]; allStatsByChannel = [allStatsByChannel; chTbl];

% --------- MASTER PLOT (placeholder) ----------
% masterFig = figure('Color','w','Position',[50 50 1400 900]);
% % Your tiledlayout + subplots go here, each subfunction returns data/images
% % you render into this single master figure.
% exportgraphics(masterFig, fullfile(inputFolder,'Master_Plot.png'), 'Resolution', 220);

% --------- SAVE STATS ----------
writetable(allStats,         fullfile(inputFolder,'Pipeline_GroupStats.csv'));
writetable(allStatsByChannel,fullfile(inputFolder,'Pipeline_ChannelStats.csv'));
fprintf('Saved:\n  %s\n  %s\n', ...
    fullfile(inputFolder,'Pipeline_GroupStats.csv'), ...
    fullfile(inputFolder,'Pipeline_ChannelStats.csv'));

end

% ==========================================================
% Helpers to normalize/flatten module outputs into tables
% ==========================================================

function [grpTbl, chTbl] = statsFrom_EventStacks(out)
% out: struct returned by EventStacks_ampWidth_Avg_Pipeline
% out.groups(g) fields used:
%   .tag (string), .nEventsUsed (scalar), .ampMean (nChx1), .ampSD (nChx1),
%   .hwMean (nChx1), .hwSD (nChx1), .n (nChx1), .MU (nCh x T)
% out.channelList (1 x nCh), out.kept_channels (optional)

moduleName = "EventStacks_ampWidth_Avg";
nCh = numel(out.channelList);
if isfield(out,'kept_channels') && ~isempty(out.kept_channels)
    csc = out.kept_channels(:);
    if numel(csc) < max(out.channelList)
        csc(end+1:max(out.channelList)) = NaN; %#ok<AGROW>
    end
else
    csc = nan(max(out.channelList),1);
end

% Preallocate empty tables
grpTbl = table('Size',[0 8], ...
    'VariableTypes', {'string','string','double','double','double','double','double','double'}, ...
    'VariableNames', {'Module','Group','NEvents','NChannels','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});

chTbl  = table('Size',[0 9], ...
    'VariableTypes', {'string','string','double','double','double','double','double','double','double'}, ...
    'VariableNames', {'Module','Group','ChannelIndex','CSC','NUsed','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});

for g = 1:numel(out.groups)
    G = out.groups(g);
    groupTag = string(G.tag);

    % ---- group-level scalars (collapse vectors) ----
    ampMean_scalar = mean(G.ampMean, 'omitnan');
    ampSD_scalar   = mean(G.ampSD,   'omitnan');   % average SD across channels (or replace with pooled, if you prefer)
    hwMean_scalar  = mean(G.hwMean,  'omitnan');
    hwSD_scalar    = mean(G.hwSD,    'omitnan');

    rowG = table(moduleName, groupTag, ...
                 double(G.nEventsUsed), double(nCh), ...
                 double(ampMean_scalar), double(ampSD_scalar), ...
                 double(hwMean_scalar),  double(hwSD_scalar), ...
                 'VariableNames', {'Module','Group','NEvents','NChannels','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});
    grpTbl = [grpTbl; rowG];

    % ---- per-channel tall rows ----
    for k = 1:nCh
        ch = out.channelList(k);
        rowC = table(moduleName, groupTag, ...
                     double(ch), double(getVal(csc, ch)), ...
                     double(G.n(k)), ...
                     double(G.ampMean(k)), double(G.ampSD(k)), ...
                     double(G.hwMean(k)),  double(G.hwSD(k)), ...
                     'VariableNames', {'Module','Group','ChannelIndex','CSC','NUsed','AmpMean_uV','AmpSD_uV','HW_Mean_ms','HW_SD_ms'});
        chTbl = [chTbl; rowC];
    end
end
end

function v = getVal(vec, idx)
if idx>=1 && idx<=numel(vec) && ~isempty(vec(idx))
    v = vec(idx);
else
    v = NaN;
end
end
