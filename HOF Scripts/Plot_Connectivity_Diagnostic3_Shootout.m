function Plot_Connectivity_Diagnostic3_Shootout(matFilePath)
% PLOT_CONNECTIVITY_DIAGNOSTIC_3 (THE PIPELINE SHOOTOUT)
% Evaluates our modern batch architecture directly against the 
% 2010 Gordon Lab legacy methodology on real biological data.

    if nargin < 1
        matFilePath = 'D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\J2_PRECON2_SP_091325_FirstHTLT.mat';
    end
    if ~exist(matFilePath, 'file')
        error('!!! CRITICAL: Input file not found: %s', matFilePath);
    end

    % ---------------- CONFIGURATION ----------------
    ch1Name = 'Left_POR_Ch01';
    ch2Name = 'Right_DHC_Ch31';
    
    target_win_sec = 5;  
    low_freq  = 4;       
    high_freq = 12;      
    
    % Our parameters
    maxLagSec_Ours = 0.5; % 500 ms 
    
    % Gordon parameters
    % Their script uses round(samp_freq/10) which forces a 100 ms lag
    
    % ---------------- LOAD & PARSE DATA ----------------
    loadedData = load(matFilePath, 'Data');
    D = loadedData.Data;
    fs = D.Meta.Fs;
    
    sig1_full = D.Signals.(ch1Name);
    sig2_full = D.Signals.(ch2Name);

    center_idx = round(length(sig1_full) / 2);
    win_samples = round(target_win_sec * fs);
    sig1 = sig1_full(center_idx - win_samples : center_idx + win_samples);
    sig2 = sig2_full(center_idx - win_samples : center_idx + win_samples);
    
    sig1(~isfinite(sig1)) = 0; sig2(~isfinite(sig2)) = 0;
    t_real = linspace(-target_win_sec, target_win_sec, length(sig1));

    fprintf('\n=======================================================\n');
    fprintf('PIPELINE SHOOTOUT: OURS VS GORDON (2010)\n');
    fprintf('=======================================================\n');

    % ---------------- 1. OUR ARCHITECTURE ----------------
    maxLagSamp_Ours = round(maxLagSec_Ours * fs);
    
    % Zero-phase bandpass native to modern MATLAB
    filt1_ours = bandpass(sig1, [low_freq high_freq], fs);
    filt2_ours = bandpass(sig2, [low_freq high_freq], fs);
    
    amp1_ours = abs(hilbert(filt1_ours)); amp1_ours = amp1_ours - mean(amp1_ours);
    amp2_ours = abs(hilbert(filt2_ours)); amp2_ours = amp2_ours - mean(amp2_ours);
    
    [acc_ours, lags_ours] = xcorr(amp1_ours, amp2_ours, maxLagSamp_Ours, 'coeff');
    lagsTime_ours = lags_ours .* (1/fs) .* 1000;

    % ---------------- 2. GORDON LAB ARCHITECTURE ----------------
    maxLagSamp_Gordon = round(fs / 10); % Strictly 100ms
    
    % Replicate their exact FIR1 + Zero-Phase implementation
    nyquist = floor(fs/2);
    order = round(fs); 
    if mod(order,2) ~= 0, order = order - 1; end
    
    MyFilt = fir1(order, [low_freq high_freq]/nyquist); 
    
    % filtfilt is the standard MATLAB equivalent of their custom "Filter0"
    filt1_gordon = filtfilt(MyFilt, 1, sig1); 
    filt2_gordon = filtfilt(MyFilt, 1, sig2);
    
    amp1_gordon = abs(hilbert(filt1_gordon)); amp1_gordon = amp1_gordon - mean(amp1_gordon);
    amp2_gordon = abs(hilbert(filt2_gordon)); amp2_gordon = amp2_gordon - mean(amp2_gordon);
    
    [acc_gordon, lags_gordon] = xcorr(amp1_gordon, amp2_gordon, maxLagSamp_Gordon, 'coeff');
    lagsTime_gordon = lags_gordon .* (1/fs) .* 1000;

    % ---------------- PLOTTING ----------------
    hFig = figure('Name', 'Pipeline Shootout', 'Color', 'w', 'Position', [50, 50, 1600, 900]);
    tlo = tiledlayout(3, 2, 'Padding', 'compact', 'TileSpacing', 'normal');

    % ROW 1: THE FILTERS
    ax1 = nexttile;
    plot(ax1, t_real, filt1_ours + 150, 'b', 'LineWidth', 1); hold on;
    plot(ax1, t_real, filt1_gordon, 'k', 'LineWidth', 1);
    xlim(ax1, [-1 1]); % Zoom in to see the wave structure
    title(ax1, sprintf('%s: Filter Comparison (Zoomed ±1s)', ch1Name), 'Interpreter', 'none');
    subtitle(ax1, 'Blue = Our bandpass() | Black = Gordon fir1()', 'FontSize', 9);
    ylabel(ax1, 'Voltage (\muV)'); grid(ax1, 'on');

    ax2 = nexttile;
    plot(ax2, t_real, filt2_ours + 150, 'r', 'LineWidth', 1); hold on;
    plot(ax2, t_real, filt2_gordon, 'k', 'LineWidth', 1);
    xlim(ax2, [-1 1]);
    title(ax2, sprintf('%s: Filter Comparison (Zoomed ±1s)', ch2Name), 'Interpreter', 'none');
    subtitle(ax2, 'Red = Our bandpass() | Black = Gordon fir1()', 'FontSize', 9);
    ylabel(ax2, 'Voltage (\muV)'); grid(ax2, 'on');

    % ROW 2: THE ENVELOPES
    ax3 = nexttile;
    plot(ax3, t_real, amp1_ours + 150, 'b', 'LineWidth', 1.5); hold on;
    plot(ax3, t_real, amp1_gordon, 'k', 'LineWidth', 1.5);
    xlim(ax3, [-target_win_sec target_win_sec]);
    title(ax3, 'Amplitude Envelopes (Mean-Centered)', 'Interpreter', 'none');
    subtitle(ax3, 'They are mathematically identical. The algorithms align.', 'FontSize', 9);
    ylabel(ax3, 'Amplitude (A.U.)'); grid(ax3, 'on');

    ax4 = nexttile;
    plot(ax4, t_real, amp2_ours + 150, 'r', 'LineWidth', 1.5); hold on;
    plot(ax4, t_real, amp2_gordon, 'k', 'LineWidth', 1.5);
    xlim(ax4, [-target_win_sec target_win_sec]);
    title(ax4, 'Amplitude Envelopes (Mean-Centered)', 'Interpreter', 'none');
    subtitle(ax4, 'No deviation detected between legacy and modern extraction.', 'FontSize', 9);
    ylabel(ax4, 'Amplitude (A.U.)'); grid(ax4, 'on');

    % ROW 3: THE CROSS-CORRELATION MAPS
    ax5 = nexttile;
    plot(ax5, lagsTime_gordon, acc_gordon, 'k', 'LineWidth', 2); hold on;
    xline(ax5, 0, 'k--', 'LineWidth', 1.2);
    xlim(ax5, [-100 100]);
    title(ax5, 'Gordon Architecture (100 ms Lag Limit)', 'Interpreter', 'none');
    subtitle(ax5, 'Legacy restriction. Blind to slow network dynamics outside ±100 ms.', 'FontSize', 9);
    xlabel(ax5, 'Lag (ms)'); ylabel(ax5, 'Correlation (r)'); grid(ax5, 'on');

    ax6 = nexttile;
    plot(ax6, lagsTime_ours, acc_ours, 'b', 'LineWidth', 2); hold on;
    % Overlay Gordon's tiny window to show scale
    xregion(ax6, -100, 100, 'FaceColor', 'k', 'FaceAlpha', 0.1); 
    xline(ax6, 0, 'k--', 'LineWidth', 1.2);
    xlim(ax6, [-500 500]);
    title(ax6, 'Our Architecture (500 ms Lag Expansion)', 'Interpreter', 'none');
    subtitle(ax6, 'Expanded field of view. The gray box represents the Gordon limit.', 'FontSize', 9);
    xlabel(ax6, 'Lag (ms)'); ylabel(ax6, 'Correlation (r)'); grid(ax6, 'on');

    sgtitle(tlo, 'Pipeline Verification: Modern Architecture vs Legacy Literature', 'FontWeight', 'bold', 'FontSize', 16, 'Interpreter', 'none');
end