function visualize_LL(inMatPath, resultsMatPath)
% Interactive viewer for disk-backed CSC data + LLspikedetector results.
% - Scroll through time
% - Select which channels to view (multi-select)
% - Event overlays (only those involving selected channels)
% - Efficient: reads only the slice shown (uses matfile)
%
% Usage:
%   visualize_LL('..._mex_disk.mat', '..._LLspikes_FAST_*.mat')

%% ---------- Load metadata & results ----------
mf = matfile(inMatPath);
nRows = size(mf,'d',1);
nCol  = size(mf,'d',2);
sfx   = mf.sfx;

ets = []; ech = []; params = struct;
if exist(resultsMatPath,'file')
    S = load(resultsMatPath,'ets','ech','params','T');
    if isfield(S,'ets'), ets = S.ets; end
    if isfield(S,'ech'), ech = S.ech; end
    if isfield(S,'params'), params = S.params; end
else
    warning('Results file not found. Proceeding without events.');
end

% Channel labeling/mapping
if isprop(mf,'kept_channels')
    kept_channels = mf.kept_channels;  % original channel numbers corresponding to rows in d
else
    kept_channels = 1:nRows;
end
labels = arrayfun(@(k) sprintf('CSC%d', kept_channels(k)), 1:nRows, 'UniformOutput',false);

badch_rows = false(1,nRows);
if isprop(mf,'badch')
    bc_full = mf.badch;
    if ~isempty(bc_full) && numel(bc_full) >= max(kept_channels)
        for i=1:nRows, badch_rows(i) = logical(bc_full(kept_channels(i))); end
    end
end

%% ---------- UI setup ----------
winSecDefault = 5;                            % default time window in seconds
winSamplesDefault = max(1, round(winSecDefault*sfx));
tMaxSec = nCol / sfx;

f  = figure('Name','LL Viewer','Color','w','NumberTitle','off','Units','normalized','Position',[0.05 0.08 0.9 0.82]);
tl = tiledlayout(f,'flow','TileSpacing','compact','Padding','compact');

ax = axes(tl); hold(ax,'on'); box(ax,'on');
title(ax, 'Signal (scroll with slider)', 'Interpreter','none');
xlabel(ax, 'Time (s)'); ylabel(ax, 'Amplitude (AD counts)');

% Controls
uip = uipanel('Parent',f,'Units','normalized','Position',[0.01 0.01 0.98 0.18],'Title','Controls','BackgroundColor','w');

uicontrol(uip,'Style','text','String','Start (s):','Units','normalized','Position',[0.01 0.64 0.07 0.25],'BackgroundColor','w','HorizontalAlignment','left');
txtStart = uicontrol(uip,'Style','edit','String','0','Units','normalized','Position',[0.08 0.64 0.08 0.28],'Callback',@onJump,'BackgroundColor','w');

uicontrol(uip,'Style','text','String','Window (s):','Units','normalized','Position',[0.18 0.64 0.08 0.25],'BackgroundColor','w','HorizontalAlignment','left');
txtWin = uicontrol(uip,'Style','edit','String',num2str(winSecDefault),'Units','normalized','Position',[0.26 0.64 0.08 0.28],'Callback',@onJump,'BackgroundColor','w');

btnPrev = uicontrol(uip,'Style','pushbutton','String','<< Prev','Units','normalized','Position',[0.36 0.64 0.08 0.28],'Callback',@(src,evt) nudge(-1));
btnNext = uicontrol(uip,'Style','pushbutton','String','Next >>','Units','normalized','Position',[0.45 0.64 0.08 0.28],'Callback',@(src,evt) nudge(+1));

uicontrol(uip,'Style','text','String','Channels:','Units','normalized','Position',[0.55 0.64 0.08 0.25],'BackgroundColor','w','HorizontalAlignment','left');
lst = uicontrol(uip,'Style','listbox','Units','normalized','Position',[0.63 0.10 0.15 0.82], ...
    'Max', 20, 'Min', 1, 'String', labels, 'Value', 1:min(4,numel(labels)), ...
    'Callback', @refreshPlot, 'BackgroundColor','w');

uicontrol(uip,'Style','text','String','Event filter:','Units','normalized','Position',[0.80 0.64 0.09 0.25],'BackgroundColor','w','HorizontalAlignment','left');
cbAny = uicontrol(uip,'Style','checkbox','String','Show all events','Units','normalized','Position',[0.80 0.52 0.18 0.12], ...
    'Value',0, 'BackgroundColor','w', 'Callback', @refreshPlot);
cbSel = uicontrol(uip,'Style','checkbox','String','Only events with selected ch','Units','normalized','Position',[0.80 0.38 0.18 0.12], ...
    'Value',1, 'BackgroundColor','w', 'Callback', @refreshPlot);

uicontrol(uip,'Style','text','String','Jump to event #','Units','normalized','Position',[0.36 0.18 0.10 0.2],'BackgroundColor','w','HorizontalAlignment','left');
txtEvt = uicontrol(uip,'Style','edit','String','', 'Units','normalized','Position',[0.46 0.18 0.05 0.25],'BackgroundColor','w');
btnEvt = uicontrol(uip,'Style','pushbutton','String','Go','Units','normalized','Position',[0.52 0.18 0.04 0.25],'Callback',@jumpToEvent);

% Slider for time
sld = uicontrol(uip,'Style','slider','Units','normalized','Position',[0.01 0.08 0.98 0.06], ...
    'Min', 0, 'Max', max(0, tMaxSec - winSecDefault), 'Value', 0, ...
    'SliderStep', [1, 10] ./ max(1, tMaxSec), 'Callback', @refreshPlot);

% Status text
txtStatus = uicontrol(uip,'Style','text','Units','normalized','Position',[0.01 0.38 0.30 0.20],'String','Ready','BackgroundColor','w','HorizontalAlignment','left');

% Store app state
state.mf     = mf;
state.sfx    = sfx;
state.nRows  = nRows;
state.nCol   = nCol;
state.ets    = ets;
state.ech    = ech;
state.labels = labels;
state.badch  = badch_rows;
state.kept   = kept_channels;

state.ax     = ax;
state.sld    = sld;
state.txtStart = txtStart;
state.txtWin = txtWin;
state.txtStatus = txtStatus;
state.lst    = lst;
state.cbAny  = cbAny;
state.cbSel  = cbSel;

guidata(f, state);
refreshPlot();

%% ---------- Callbacks ----------
    function onJump(~,~)
        st = str2double(get(txtStart,'String')); if ~isfinite(st), st=0; end
        ws = max(0.1, str2double(get(txtWin,'String'))); if ~isfinite(ws), ws = winSecDefault; end
        st = max(0, min(st, tMaxSec - ws));
        set(sld,'Value',st,'Max',max(0,tMaxSec-ws));
        set(txtStart,'String',num2str(st));
        set(txtWin,'String',num2str(ws));
        refreshPlot();
    end

    function nudge(dir)
        ws = str2double(get(txtWin,'String')); if ~isfinite(ws), ws=winSecDefault; end
        st = get(sld,'Value') + dir*ws*0.8;   % 80% window shift
        st = max(0, min(st, max(0,tMaxSec - ws)));
        set(sld,'Value',st);
        set(txtStart,'String',num2str(st));
        refreshPlot();
    end

    function jumpToEvent(~,~)
        if isempty(ets), return; end
        k = str2double(get(txtEvt,'String'));
        if ~isfinite(k) || k<1 || k>size(ets,1), return; end
        ws = str2double(get(txtWin,'String')); if ~isfinite(ws), ws=winSecDefault; end
        tCenter = mean(ets(k,:)) / sfx;
        st = max(0, min(tCenter - ws/2, max(0,tMaxSec - ws)));
        set(sld,'Value',st);
        set(txtStart,'String',num2str(st));
        refreshPlot();
    end

    function refreshPlot(~,~)
        st = get(sld,'Value');
        ws = max(0.1, str2double(get(txtWin,'String')));  % ≥100 ms
        if ~isfinite(ws), ws = winSecDefault; end
        set(sld,'Max',max(0,tMaxSec-ws));

        t0 = max(1, floor(st * sfx) + 1);
        t1 = min(state.nCol, t0 + max(1,round(ws*sfx)) - 1);

        sel = get(state.lst,'Value');
        if isempty(sel), sel = 1; end

        % Pull only the selected rows & time slice from disk
        tic;
        X = state.mf.d(sel, t0:t1);  % (k x Nwin)
        dtRead = toc;

        % Decimate if too many points (for speed)
        Nwin = size(X,2);
        targetPts = 4000;
        ds = max(1, floor(Nwin/targetPts));
        if ds > 1
            Xd = X(:,1:ds:end);
            tt = ((t0-1) + (0:ds:(Nwin-1))) / sfx;
        else
            Xd = X;
            tt = ((t0-1) + (0:(Nwin-1))) / sfx;
        end

        % Plot
        cla(state.ax);
        offset = 0;
        yGap = 0;
        if size(Xd,1) > 1
            % nice vertical separation: auto-scale each channel and offset
            scl = max(eps, prctile(abs(Xd), 99, 2));
            yGap = median(scl)*3;
        else
            scl = 1;
            yGap = 0;
        end

        for k = 1:size(Xd,1)
            y = double(Xd(k,:));
            if size(Xd,1)>1
                y = y./max(1,scl(k)) + offset;
            end
            plot(state.ax, tt, y, 'LineWidth', 1);
            text(state.ax, tt(1), (isempty(offset)*0 + offset), sprintf('%s%s', labels{sel(k)}, state.badch(sel(k))*"*"), ...
                 'VerticalAlignment','bottom','Color',[0 .4 .1]);
            offset = offset + yGap;
        end
        grid(state.ax, 'on');
        xlim(state.ax, [tt(1) tt(end)]);
        if size(Xd,1)>1
            ylim(state.ax, [ -yGap*0.5, offset + yGap*0.5 ]);
        end
        title(state.ax, sprintf('Time %.3f–%.3f s | %d ch | read %.0f ms | ds=%d', tt(1), tt(end), numel(sel), dtRead*1000, ds));

        % Overlay events
        if ~isempty(state.ets) && (get(state.cbAny,'Value') || get(state.cbSel,'Value'))
            hold(state.ax,'on');
            % Find events overlapping current window
            e_on  = state.ets(:,1) / state.sfx;
            e_off = state.ets(:,2) / state.sfx;
            inWin = (e_off >= tt(1)) & (e_on <= tt(end));
            if any(inWin)
                idx = find(inWin);
                if get(state.cbSel,'Value') && ~isempty(state.ech)
                    % keep only events involving selected rows
                    selMask = any(state.ech(idx, sel), 2);
                    idx = idx(selMask);
                end
                for ii = reshape(idx,1,[])
                    x1 = max(tt(1), e_on(ii)); x2 = min(tt(end), e_off(ii));
                    patch(state.ax, [x1 x2 x2 x1], [ylim(state.ax,[1])], [0.9 0.9 0.0], ...
                          'FaceAlpha', 0.2, 'EdgeColor','none', 'HitTest','off');
                end
            end
        end

        % status
        set(state.txtStatus,'String',sprintf('Start=%.3f s | Window=%.3f s | Ch sel=%s', tt(1), ws, strjoin(labels(sel),',')));
        drawnow;
    end
end
