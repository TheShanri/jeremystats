function Plot_Connectivity_Diagnostic2(matFilePath)
% PLOT_CONNECTIVITY_DIAGNOSTIC (AMP CC SPECIALIST)
% Evaluates real data against 3 exaggerated synthetic scenarios designed
% specifically to isolate Amplitude Cross-Correlation mechanics.

    if nargin < 1
        matFilePath = 'D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\J2_PRECON2_SP_091325_FirstHTLT.mat';
    end

    if ~exist(matFilePath, 'file')
        error('!!! CRITICAL: Input file not found: %s', matFilePath);
    end

    % ---------------- CONFIGURATION ----------------
    ch1Name = 'Left_POR_Ch01';
    ch2Name = 'Right_DHC_Ch31';
    
    target_win_sec = 5;  % +/- 5 seconds
    low_freq  = 4;       % Theta Low
    high_freq = 12;      % Theta High
    maxLagSec = 0.5;     % Analyze +/- 500 ms lag

    % ---------------- LOAD & PARSE DATA ----------------
    loadedData = load(matFilePath, 'Data');
    D = loadedData.Data;
    fs = D.Meta.Fs;
    
    sig1_full = D.Signals.(ch1Name);
    sig2_full = D.Signals.(ch2Name);

    % Crop
    center_idx = round(length(sig1_full) / 2);
    win_samples = round(target_win_sec * fs);
    sig1 = sig1_full(center_idx - win_samples : center_idx + win_samples);
    sig2 = sig2_full(center_idx - win_samples : center_idx + win_samples);
    
    sig1(~isfinite(sig1)) = 0; sig2(~isfinite(sig2)) = 0;
    t_real = linspace(-target_win_sec, target_win_sec, length(sig1));

    % ---------------- TERMINAL LOGOUT ----------------
    fprintf('\n=======================================================\n');
    fprintf('AMP CC SPECIALIST DIAGNOSTIC LOG\n');
    fprintf('=======================================================\n');
    fprintf('[METADATA]\n');
    fprintf('   Session:       %s\n', D.Meta.Session);
    fprintf('   Event:         %s (Index %d)\n', D.Meta.Event, D.Meta.EventIndex);
    fprintf('   Sampling Freq: %d Hz\n', fs);
    fprintf('\n[ANALYSIS PARAMETERS]\n');
    fprintf('   Channel 1:     %s\n', ch1Name);
    fprintf('   Channel 2:     %s\n', ch2Name);
    fprintf('   Amp Corr Band: %d - %d Hz\n', low_freq, high_freq);
    fprintf('   Max CC Lag:    +/-%.1f seconds\n', maxLagSec);
    fprintf('\n[SYNTHETIC PARAMETERS]\n');
    fprintf('   Delay Induced: +100 ms (Expected peak at -100 ms)\n');
    fprintf('   Syn 1: Perfect Envelope, Perfect Carrier (8Hz)\n');
    fprintf('   Syn 2: Perfect Envelope, Mismatched Carrier (8Hz vs 11Hz)\n');
    fprintf('   Syn 3: Inverted Envelope, Perfect Carrier (8Hz)\n');
    fprintf('=======================================================\n');

    % ---------------- 1. REAL DATA METRICS ----------------
    wsize = round(fs); noverlap = round(wsize/2); nfft = 2*wsize;
    maxLagSamp = round(maxLagSec * fs);
    
    [C_real, Fc_real] = mscohere(sig1, sig2, hanning(wsize), noverlap, nfft, fs);
    
    [ccf_real, lags_real] = xcorr(sig1, sig2, maxLagSamp, 'coeff');
    lagsTime_real = lags_real .* (1/fs) .* 1000;
    
    filt1 = bandpass(sig1, [low_freq high_freq], fs);
    filt2 = bandpass(sig2, [low_freq high_freq], fs);
    amp1 = abs(hilbert(filt1)); amp1 = amp1 - mean(amp1);
    amp2 = abs(hilbert(filt2)); amp2 = amp2 - mean(amp2);
    
    [amp_ccf_real, amp_lags_real] = xcorr(amp1, amp2, maxLagSamp, 'coeff');
    amp_lagsTime_real = amp_lags_real .* (1/fs) .* 1000;

    % ---------------- 2. SYNTHETIC SCENARIOS ----------------
    t_syn = t_real;
    shift_ms = 100; 
    shift_samp = round((shift_ms / 1000) * fs);
    
    env_base = sin(2*pi*0.5*t_syn) + 2;     % 0.5 Hz Slow Envelope
    env_inv  = -sin(2*pi*0.5*t_syn) + 2;    % Inverted Envelope
    car_8Hz  = sin(2*pi*8*t_syn);           % 8 Hz Carrier
    car_11Hz = sin(2*pi*11*t_syn);          % 11 Hz Carrier (Still in Theta band)
    noise    = 0.1 * randn(size(t_syn));

    % Scenario 1: The Perfect Clone
    s1_A = env_base .* car_8Hz + noise;
    s1_B = circshift(s1_A, shift_samp);
    
    % Scenario 2: The Amp CC Hero (Mismatched phase/frequency)
    s2_A = env_base .* car_8Hz + noise;
    s2_B = circshift((env_base .* car_11Hz + noise), shift_samp);
    
    % Scenario 3: The Anti-Correlation (Inverted Envelope)
    s3_A = env_base .* car_8Hz + noise;
    s3_B = circshift((env_inv .* car_8Hz + noise), shift_samp);

    % Process Synthetics
    function [C, Fc, ccf, lagsT, amp_ccf, amp_lagsT] = run_metrics(sA, sB)
        [C, Fc] = mscohere(sA, sB, hanning(wsize), noverlap, nfft, fs);
        [ccf, lags] = xcorr(sA, sB, maxLagSamp, 'coeff');
        lagsT = lags .* (1/fs) .* 1000;
        
        fA = bandpass(sA, [low_freq high_freq], fs);
        fB = bandpass(sB, [low_freq high_freq], fs);
        aA = abs(hilbert(fA)); aA = aA - mean(aA);
        aB = abs(hilbert(fB)); aB = aB - mean(aB);
        [amp_ccf, alags] = xcorr(aA, aB, maxLagSamp, 'coeff');
        amp_lagsT = alags .* (1/fs) .* 1000;
    end

    [C1, Fc1, cc1, lt1, acc1, alt1] = run_metrics(s1_A, s1_B);
    [C2, Fc2, cc2, lt2, acc2, alt2] = run_metrics(s2_A, s2_B);
    [C3, Fc3, cc3, lt3, acc3, alt3] = run_metrics(s3_A, s3_B);

    % ---------------- PLOTTING ----------------
    hFig = figure('Name', 'Amp CC Exaggerations', 'Color', 'w', 'Position', [10, 50, 1800, 950]);
    tlo = tiledlayout(4, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

    % Helper for plotting rows
    function plot_row(row_idx, t_vec, sigA, sigB, Fc, C, lt, cc, alt, acc, title_prefix, sub_wav, sub_coh, sub_cc, sub_acc, expected_lag)
        % 1. Waveform
        ax1 = nexttile((row_idx-1)*4 + 1);
        plot(ax1, t_vec, sigA + max(abs(sigA))*1.5, 'b', 'LineWidth', 0.8); hold on;
        plot(ax1, t_vec, sigB, 'r', 'LineWidth', 0.8);
        xlim(ax1, [-target_win_sec, target_win_sec]);
        title(ax1, sprintf('%s Waveforms', title_prefix), 'Interpreter', 'none');
        subtitle(ax1, sub_wav, 'FontSize', 8, 'Interpreter', 'none', 'Color', '#555');
        if row_idx == 1, legend(ax1, {ch1Name, ch2Name}, 'Location', 'northeast', 'Interpreter', 'none'); end
        grid(ax1, 'on');

        % 2. Coherence
        ax2 = nexttile((row_idx-1)*4 + 2);
        plot(ax2, Fc, C, 'k', 'LineWidth', 1.5);
        xlim(ax2, [0 20]); ylim(ax2, [0 1.1]);
        title(ax2, 'Coherence', 'Interpreter', 'none');
        subtitle(ax2, sub_coh, 'FontSize', 8, 'Interpreter', 'none', 'Color', '#d62728');
        grid(ax2, 'on');

        % 3. Raw CC
        ax3 = nexttile((row_idx-1)*4 + 3);
        plot(ax3, lt, cc, 'b', 'LineWidth', 1.5); hold on;
        xline(ax3, 0, 'k--', 'LineWidth', 1.2);
        if ~isnan(expected_lag), xline(ax3, -expected_lag, 'g-', 'LineWidth', 1.5); end
        xlim(ax3, [-maxLagSec*1000, maxLagSec*1000]); ylim(ax3, [-1.1 1.1]);
        title(ax3, 'Raw CC', 'Interpreter', 'none');
        subtitle(ax3, sub_cc, 'FontSize', 8, 'Interpreter', 'none', 'Color', '#d62728');
        grid(ax3, 'on');

        % 4. Amp CC
        ax4 = nexttile((row_idx-1)*4 + 4);
        plot(ax4, alt, acc, 'r', 'LineWidth', 2); hold on;
        xline(ax4, 0, 'k--', 'LineWidth', 1.2);
        if ~isnan(expected_lag), xline(ax4, -expected_lag, 'g-', 'LineWidth', 1.5); end
        xlim(ax4, [-maxLagSec*1000, maxLagSec*1000]); ylim(ax4, [-1.1 1.1]);
        title(ax4, sprintf('Amp CC (%d-%d Hz)', low_freq, high_freq), 'Interpreter', 'none');
        subtitle(ax4, sub_acc, 'FontSize', 8, 'Interpreter', 'none', 'Color', '#2ca02c');
        grid(ax4, 'on');
    end

    % Row 1: Real
    plot_row(1, t_real, sig1, sig2, Fc_real, C_real, lagsTime_real, ccf_real, amp_lagsTime_real, amp_ccf_real, ...
        'REAL DATA', 'Biological Signal', 'Real Phase Consistency', 'Real Wave Correlation', 'Real Power Covariance', NaN);

    % Row 2: Syn 1 (Base)
    plot_row(2, t_syn, s1_A, s1_B, Fc1, C1, lt1, cc1, alt1, acc1, ...
        'SYN 1: Clone', 'Env Match | 8Hz vs 8Hz', 'ROI: Perfect Phase Match = 1.0', 'ROI: Perfect Wave Match', 'ROI: Perfect Env Match', shift_ms);

    % Row 3: Syn 2 (Phase Scrambled - Amp CC Hero)
    plot_row(3, t_syn, s2_A, s2_B, Fc2, C2, lt2, cc2, alt2, acc2, ...
        'SYN 2: Scrambled', 'Env Match | 8Hz vs 11Hz', 'ROI: Freq Mismatch = 0 Coh', 'ROI: Waves fail to align', 'ROI: HERO! Still catches Env Lag', shift_ms);

    % Row 4: Syn 3 (Inverted Env)
    plot_row(4, t_syn, s3_A, s3_B, Fc3, C3, lt3, cc3, alt3, acc3, ...
        'SYN 3: Inverted', 'Env Inverted | 8Hz vs 8Hz', 'ROI: Carrier still locked', 'ROI: Waves align', 'ROI: NEGATIVE corr (-1.0)', shift_ms);

    sgtitle(tlo, 'Amp CC Isolation Diagnostics: Real Data vs Exaggerated Mechanics', 'FontWeight', 'bold', 'FontSize', 16, 'Interpreter', 'none');
end