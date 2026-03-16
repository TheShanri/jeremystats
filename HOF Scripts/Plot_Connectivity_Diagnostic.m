function Plot_Connectivity_Diagnostic(matFilePath)
% PLOT_CONNECTIVITY_DIAGNOSTIC (COMBO EVENT + SYNTHETIC SANITY CHECKS)
% Extracts the +/- 5s window from a combo .mat file, computes 3 metrics,
% and validates the math against perfect synthetic data.
%
% USAGE:
%   Plot_Connectivity_Diagnostic('D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\J2_PRECON2_SP_091325_FirstHTLT.mat')

    if nargin < 1
        matFilePath = 'D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\J2_PRECON2_SP_091325_FirstHTLT.mat';
    end

    if ~exist(matFilePath, 'file')
        error('!!! CRITICAL: Input file not found: %s', matFilePath);
    end

    % ---------------- CONFIGURATION ----------------
    % Brain regions to compare
    ch1Name = 'Left_POR_Ch01';
    ch2Name = 'Right_DHC_Ch31';
    
    % Crop Window
    target_win_sec = 5; % +/- 5 seconds
    
    % Amplitude Cross-Correlation Bandpass
    low_freq  = 4;  % Theta Low
    high_freq = 12; % Theta High
    
    % Cross-Correlation Window
    maxLagSec = 0.5; % Analyze +/- 500 ms lag

    % ---------------- LOAD & PARSE DATA ----------------
    loadedData = load(matFilePath, 'Data');
    if ~isfield(loadedData, 'Data')
        error('The file does not contain the expected "Data" structure.');
    end
    D = loadedData.Data;
    
    fs = D.Meta.Fs;
    midTime = D.Meta.Midpoint_Time_Sec;
    
    try
        sig1_full = D.Signals.(ch1Name);
        sig2_full = D.Signals.(ch2Name);
    catch
        error('Channels %s or %s not found in the file.', ch1Name, ch2Name);
    end

    % ---------------- CROP TO +/- 5 SECONDS ----------------
    total_samples = length(sig1_full);
    center_idx = round(total_samples / 2);
    win_samples = round(target_win_sec * fs);
    
    start_idx = max(1, center_idx - win_samples);
    end_idx   = min(total_samples, center_idx + win_samples);
    
    sig1 = sig1_full(start_idx:end_idx);
    sig2 = sig2_full(start_idx:end_idx);
    
    % Clean NaNs
    sig1(~isfinite(sig1)) = 0;
    sig2(~isfinite(sig2)) = 0;
    
    t_real = linspace(-target_win_sec, target_win_sec, length(sig1));

    % ---------------- TERMINAL LOGOUT ----------------
    fprintf('\n=======================================================\n');
    fprintf('CONNECTIVITY DIAGNOSTIC LOG\n');
    fprintf('=======================================================\n');
    fprintf('[METADATA]\n');
    fprintf('   Session:       %s\n', D.Meta.Session);
    fprintf('   Event:         %s (Index %d)\n', D.Meta.Event, D.Meta.EventIndex);
    fprintf('   Midpoint Time: %.3f seconds\n', midTime);
    fprintf('   Sampling Freq: %d Hz\n', fs);
    fprintf('\n[ANALYSIS PARAMETERS]\n');
    fprintf('   Channel 1:     %s\n', ch1Name);
    fprintf('   Channel 2:     %s\n', ch2Name);
    fprintf('   Crop Window:   +/-%d seconds (%d samples total)\n', target_win_sec, length(sig1));
    fprintf('   Amp Corr Band: %d - %d Hz\n', low_freq, high_freq);
    fprintf('   Max CC Lag:    +/-%.1f seconds\n', maxLagSec);
    fprintf('=======================================================\n');

    % ---------------- 1. REAL DATA METRICS ----------------
    wsize = round(fs); 
    noverlap = round(wsize/2);
    nfft = 2*wsize;
    maxLagSamp = round(maxLagSec * fs);
    
    % A. Coherence
    [C_real, Fc_real] = mscohere(sig1, sig2, hanning(wsize), noverlap, nfft, fs);
    
    % B. Raw Cross-Correlation
    [ccf_real, lags_real] = xcorr(sig1, sig2, maxLagSamp, 'coeff');
    lagsTime_real = lags_real .* (1/fs) .* 1000;
    
    % C. Amplitude Cross-Correlation
    filt1 = bandpass(sig1, [low_freq high_freq], fs);
    filt2 = bandpass(sig2, [low_freq high_freq], fs);
    
    amp1 = abs(hilbert(filt1)); amp1 = amp1 - mean(amp1);
    amp2 = abs(hilbert(filt2)); amp2 = amp2 - mean(amp2);
    
    [amp_ccf_real, amp_lags_real] = xcorr(amp1, amp2, maxLagSamp, 'coeff');
    amp_lagsTime_real = amp_lags_real .* (1/fs) .* 1000;

    % ---------------- 2. SYNTHETIC SANITY CHECKS ----------------
    % Generate a perfect Theta wave (8Hz) modulated by a slow wave (0.5Hz)
    % Shift signal 2 exactly 75ms into the future. Add 10% white noise.
    
    t_syn = linspace(-target_win_sec, target_win_sec, length(sig1));
    syn_envelope = sin(2*pi*0.5*t_syn) + 2; % 0.5 Hz envelope
    syn_carrier  = sin(2*pi*8*t_syn);       % 8 Hz Theta Carrier
    
    syn1 = syn_envelope .* syn_carrier + 0.1 * randn(size(t_syn));
    
    shift_ms = 75; 
    shift_samp = round((shift_ms / 1000) * fs);
    syn2 = circshift(syn1, shift_samp);
    
    % A. Syn Coherence
    [C_syn, Fc_syn] = mscohere(syn1, syn2, hanning(wsize), noverlap, nfft, fs);
    
    % B. Syn Raw Cross-Correlation
    [ccf_syn, lags_syn] = xcorr(syn1, syn2, maxLagSamp, 'coeff');
    lagsTime_syn = lags_syn .* (1/fs) .* 1000;
    
    % C. Syn Amplitude Cross-Correlation
    s_filt1 = bandpass(syn1, [low_freq high_freq], fs);
    s_filt2 = bandpass(syn2, [low_freq high_freq], fs);
    s_amp1 = abs(hilbert(s_filt1)); s_amp1 = s_amp1 - mean(s_amp1);
    s_amp2 = abs(hilbert(s_filt2)); s_amp2 = s_amp2 - mean(s_amp2);
    
    [amp_ccf_syn, amp_lags_syn] = xcorr(s_amp1, s_amp2, maxLagSamp, 'coeff');
    amp_lagsTime_syn = amp_lags_syn .* (1/fs) .* 1000;

    % ---------------- PLOTTING ----------------
    hFig = figure('Name', 'Connectivity Diagnostic', 'Color', 'w', 'Position', [50, 50, 1600, 800]);
    tlo = tiledlayout(2, 4, 'Padding', 'compact', 'TileSpacing', 'normal');

    % --- ROW 1: REAL DATA ---
    % Plot 1.1: Raw Waveform
    ax1 = nexttile(tlo);
    plot(ax1, t_real, sig1 + max(abs(sig1))*1.5, 'b', 'LineWidth', 0.8); hold on;
    plot(ax1, t_real, sig2, 'r', 'LineWidth', 0.8);
    xlim(ax1, [-target_win_sec, target_win_sec]);
    title(ax1, 'Raw EEG Waveforms', 'Interpreter', 'none');
    subtitle(ax1, sprintf('Fs: %d Hz | Window: ±%d s', fs, target_win_sec), 'FontSize', 8, 'Interpreter', 'none');
    ylabel(ax1, 'Voltage (\muV)', 'Interpreter', 'none');
    legend(ax1, {ch1Name, ch2Name}, 'Location', 'northeast', 'Interpreter', 'none');
    grid(ax1, 'on');

    % Plot 1.2: Real Coherence
    ax2 = nexttile(tlo);
    plot(ax2, Fc_real, C_real, 'k', 'LineWidth', 1.5);
    xlim(ax2, [0 50]); ylim(ax2, [0 1]);
    title(ax2, 'Magnitude-Squared Coherence', 'Interpreter', 'none');
    subtitle(ax2, sprintf('Win: hanning(%d) | Noverlap: %d | NFFT: %d', wsize, noverlap, nfft), 'FontSize', 8, 'Interpreter', 'none');
    xlabel(ax2, 'Frequency (Hz)', 'Interpreter', 'none'); ylabel(ax2, 'Coherence', 'Interpreter', 'none');
    grid(ax2, 'on');

    % Plot 1.3: Real CC
    ax3 = nexttile(tlo);
    plot(ax3, lagsTime_real, ccf_real, 'b', 'LineWidth', 1.5);
    xline(ax3, 0, 'k--', 'LineWidth', 1.2);
    xlim(ax3, [-maxLagSec*1000, maxLagSec*1000]);
    title(ax3, 'Raw Cross-Correlation', 'Interpreter', 'none');
    subtitle(ax3, sprintf('Max Lag: ±%d ms | Norm: ''coeff''', maxLagSec*1000), 'FontSize', 8, 'Interpreter', 'none');
    xlabel(ax3, 'Lag (ms) [Negative = Ch2 lags Ch1]', 'Interpreter', 'none'); ylabel(ax3, 'Correlation (r)', 'Interpreter', 'none');
    grid(ax3, 'on');

    % Plot 1.4: Real Amp CC
    ax4 = nexttile(tlo);
    plot(ax4, amp_lagsTime_real, amp_ccf_real, 'r', 'LineWidth', 1.5);
    xline(ax4, 0, 'k--', 'LineWidth', 1.2);
    xlim(ax4, [-maxLagSec*1000, maxLagSec*1000]);
    title(ax4, sprintf('Amp Cross-Corr (%d-%d Hz)', low_freq, high_freq), 'Interpreter', 'none');
    subtitle(ax4, sprintf('Filter: bandpass() | Env: abs(hilbert()) | Max Lag: ±%d ms', maxLagSec*1000), 'FontSize', 8, 'Interpreter', 'none');
    xlabel(ax4, 'Lag (ms) [Negative = Ch2 lags Ch1]', 'Interpreter', 'none'); ylabel(ax4, 'Correlation (r)', 'Interpreter', 'none');
    grid(ax4, 'on');

    % --- ROW 2: SYNTHETIC DATA ---
    % Plot 2.1: Syn Waveform
    ax5 = nexttile(tlo);
    plot(ax5, t_syn, syn1 + 3, 'b', 'LineWidth', 0.8); hold on;
    plot(ax5, t_syn, syn2, 'r', 'LineWidth', 0.8);
    xlim(ax5, [-target_win_sec, target_win_sec]);
    title(ax5, 'Synthetic Sanity Check', 'Interpreter', 'none');
    subtitle(ax5, 'Carrier: 8Hz | Env: 0.5Hz | Noise: 10% | Shift: +75ms', 'FontSize', 8, 'Interpreter', 'none');
    ylabel(ax5, 'Amplitude (A.U.)', 'Interpreter', 'none');
    legend(ax5, {'Syn 1 (Base)', 'Syn 2 (Delayed)'}, 'Location', 'northeast', 'Interpreter', 'none');
    grid(ax5, 'on');

    % Plot 2.2: Syn Coherence
    ax6 = nexttile(tlo);
    plot(ax6, Fc_syn, C_syn, 'k', 'LineWidth', 1.5);
    xlim(ax6, [0 50]); ylim(ax6, [0 1.1]);
    title(ax6, 'Sanity: Coherence (~1.0 @ 8Hz)', 'Interpreter', 'none');
    subtitle(ax6, sprintf('Win: hanning(%d) | Noverlap: %d | NFFT: %d', wsize, noverlap, nfft), 'FontSize', 8, 'Interpreter', 'none');
    xlabel(ax6, 'Frequency (Hz)', 'Interpreter', 'none'); ylabel(ax6, 'Coherence', 'Interpreter', 'none');
    grid(ax6, 'on');

    % Plot 2.3: Syn CC
    ax7 = nexttile(tlo);
    plot(ax7, lagsTime_syn, ccf_syn, 'b', 'LineWidth', 1.5);
    xline(ax7, 0, 'k--', 'LineWidth', 1.2);
    xline(ax7, -shift_ms, 'g-', 'LineWidth', 1.5); % Mark correct mathematical negative lag
    xlim(ax7, [-maxLagSec*1000, maxLagSec*1000]);
    title(ax7, sprintf('Sanity: Raw CC (~1.0 @ -%dms)', shift_ms), 'Interpreter', 'none');
    subtitle(ax7, sprintf('Norm: ''coeff'' | Green Line = Math Peak (-%dms)', shift_ms), 'FontSize', 8, 'Interpreter', 'none');
    xlabel(ax7, 'Lag (ms) [Negative = Syn2 lags Syn1]', 'Interpreter', 'none'); ylabel(ax7, 'Correlation (r)', 'Interpreter', 'none');
    grid(ax7, 'on');

    % Plot 2.4: Syn Amp CC
    ax8 = nexttile(tlo);
    plot(ax8, amp_lagsTime_syn, amp_ccf_syn, 'r', 'LineWidth', 1.5);
    xline(ax8, 0, 'k--', 'LineWidth', 1.2);
    xline(ax8, -shift_ms, 'g-', 'LineWidth', 1.5); % Mark correct mathematical negative lag
    xlim(ax8, [-maxLagSec*1000, maxLagSec*1000]);
    title(ax8, sprintf('Sanity: Amp CC (%d-%d Hz)', low_freq, high_freq), 'Interpreter', 'none');
    subtitle(ax8, sprintf('Env: abs(hilbert()) | Green Line = Math Peak (-%dms)', shift_ms), 'FontSize', 8, 'Interpreter', 'none');
    xlabel(ax8, 'Lag (ms) [Negative = Syn2 lags Syn1]', 'Interpreter', 'none'); ylabel(ax8, 'Correlation (r)', 'Interpreter', 'none');
    grid(ax8, 'on');

    sgtitle(tlo, sprintf('%s: Real Data vs Perfect Synthetic Benchmark', D.Meta.Session), 'FontWeight', 'bold', 'FontSize', 14, 'Interpreter', 'none');
end