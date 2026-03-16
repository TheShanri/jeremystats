function Plot_Connectivity_Synthetic_Masterclass(matFilePath)
% PLOT_CONNECTIVITY_SYNTHETIC_MASTERCLASS (BIOLOGICAL INTEGRATION)
% A robust theoretical proving ground for connectivity mathematics.
% Deploys 4 extreme synthetic edge-cases alongside 1 real biological sample 
% to isolate and prove Phase, Waveform, and Envelope dynamics.

    if nargin < 1
        matFilePath = 'D:\HOF DATA\ACTIVE DATA\PYTHON_UI_DATA\J2_PRECON2_SP_091325_FirstHTLT.mat';
    end

    fprintf('\n=======================================================\n');
    fprintf('SYNTHETIC MATHEMATICS MASTERCLASS + BIOLOGICAL TRUTH\n');
    fprintf('=======================================================\n');

    % ---------------- 1. UNIVERSAL LAWS ----------------
    fs = 1000; % 1 kHz sampling baseline
    target_win_sec = 5; 
    t = linspace(-target_win_sec, target_win_sec, target_win_sec * 2 * fs);
    
    low_freq = 4; high_freq = 12; % Theta Band limits
    maxLagSec = 0.5; maxLagSamp = round(maxLagSec * fs);
    wsize = fs; noverlap = round(wsize/2); nfft = 2*wsize;
    
    shift_ms = 100; % Hardcoded 100ms delay for the synthetic lagging signals
    shift_samp = round((shift_ms / 1000) * fs);

    % ---------------- 2. THE THEORETICAL CONSTRUCTS ----------------
    % We construct the pure mathematical components.
    env_slow = sin(2*pi*0.5*t) + 2;      % 0.5 Hz Slow Power Fluctuation (Envelope)
    env_inv  = -sin(2*pi*0.5*t) + 2;     % Inverted Envelope (Exact opposite power state)
    
    car_8Hz  = sin(2*pi*8*t);            % 8 Hz Carrier Wave (Standard Theta)
    car_11Hz = sin(2*pi*11*t);           % 11 Hz Carrier Wave (Fast Theta)
    
    noise_A = 0.2 * randn(size(t));
    noise_B = 0.2 * randn(size(t));

    % SCENARIO 1: The Perfect Clone (Base Truth)
    % Theory: Identical phase, identical envelope. Pure physical delay.
    % Expectation: All three metrics perfectly identify the -100ms lag.
    S1_A = env_slow .* car_8Hz + noise_A;
    S1_B = circshift(env_slow .* car_8Hz, shift_samp) + noise_B;

    % SCENARIO 2: Phase Scrambled (The Envelope Hero)
    % Theory: The network communicates via power (envelopes match), 
    % but the raw firing frequencies are misaligned (8 Hz vs 11 Hz).
    % Expectation: Coherence dies. Raw CC fails. Amp CC survives and finds the lag.
    S2_A = env_slow .* car_8Hz + noise_A;
    S2_B = circshift(env_slow .* car_11Hz, shift_samp) + noise_B;

    % SCENARIO 3: Anti-Correlation (The Inverted Envelope)
    % Theory: Phase is locked (8Hz vs 8Hz), but when Region A gains power, Region B loses power.
    % Expectation: Coherence is high. Raw CC aligns. Amp CC hits perfect -1.0.
    S3_A = env_slow .* car_8Hz + noise_A;
    S3_B = circshift(env_inv .* car_8Hz, shift_samp) + noise_B;

    % SCENARIO 4: The Null Hypothesis (Pure Chaos)
    % Theory: Two disconnected regions firing random broadband noise.
    % Expectation: Utter flatline across all metrics. Proves no false positive susceptibility.
    S4_A = randn(size(t));
    S4_B = randn(size(t));

    % ---------------- 3. THE BIOLOGICAL CONSTRUCT ----------------
    if ~exist(matFilePath, 'file')
        error('!!! CRITICAL: Biological input file not found: %s', matFilePath);
    end
    
    loadedData = load(matFilePath, 'Data');
    D = loadedData.Data;
    real_fs = D.Meta.Fs;
    
    sig1_full = double(D.Signals.Left_POR_Ch01);
    sig2_full = double(D.Signals.Right_DHC_Ch31);
    
    % Crop original data
    center_idx = round(length(sig1_full) / 2);
    win_samples = round(target_win_sec * real_fs);
    R_A_raw = sig1_full(center_idx - win_samples : center_idx + win_samples - 1);
    R_B_raw = sig2_full(center_idx - win_samples : center_idx + win_samples - 1);
    
    R_A_raw(~isfinite(R_A_raw)) = 0; 
    R_B_raw(~isfinite(R_B_raw)) = 0;
    
    % Decimate down to match the 1000 Hz synthetic timeline constraints
    ds_factor = round(real_fs / fs);
    if ds_factor > 1
        S5_A = decimate(R_A_raw, ds_factor);
        S5_B = decimate(R_B_raw, ds_factor);
    else
        S5_A = R_A_raw;
        S5_B = R_B_raw;
    end
    
    % Enforce precise array length matching for the plotting engine
    S5_A = S5_A(1:length(t));
    S5_B = S5_B(1:length(t));

    % ---------------- 4. THE MATHEMATICAL ENGINE ----------------
    function [C, Fc, ccf, lagsT, acc, alagsT] = compute_metrics(sigA, sigB)
        % Metric 1: Magnitude-Squared Coherence (Phase Consistency)
        % Welch's method. Blind to amplitude. Sees only phase alignment.
        [C, Fc] = mscohere(sigA, sigB, hanning(wsize), noverlap, nfft, fs);
        
        % Metric 2: Raw Cross-Correlation (Waveform Similarity)
        % Demands perfect peak-to-peak alignment of the broadband trace.
        [ccf, lags] = xcorr(sigA, sigB, maxLagSamp, 'coeff');
        lagsT = lags .* (1/fs) .* 1000;
        
        % Metric 3: Amplitude Cross-Correlation (Power Covariance)
        % Bandpass -> Hilbert -> Mean-Center -> Cross-Correlate.
        % Strips the carrier to isolate slow network power states.
        fA = bandpass(sigA, [low_freq high_freq], fs);
        fB = bandpass(sigB, [low_freq high_freq], fs);
        
        aA = abs(hilbert(fA)); aA = aA - mean(aA); % MANDATORY: Strip DC offset
        aB = abs(hilbert(fB)); aB = aB - mean(aB);
        
        [acc, alags] = xcorr(aA, aB, maxLagSamp, 'coeff');
        alagsT = alags .* (1/fs) .* 1000;
    end

    % Process scenarios through the engine
    [C1, F1, rCC1, L1, aCC1, aL1] = compute_metrics(S1_A, S1_B);
    [C2, F2, rCC2, L2, aCC2, aL2] = compute_metrics(S2_A, S2_B);
    [C3, F3, rCC3, L3, aCC3, aL3] = compute_metrics(S3_A, S3_B);
    [C4, F4, rCC4, L4, aCC4, aL4] = compute_metrics(S4_A, S4_B);
    [C5, F5, rCC5, L5, aCC5, aL5] = compute_metrics(S5_A, S5_B); % Biological data

    % ---------------- 5. VISUALIZATION & ANNOTATION ----------------
    hFig = figure('Name', 'Synthetic Masterclass + Real Data', 'Color', 'w', 'Position', [10, 50, 1800, 1200]);
    tlo = tiledlayout(5, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

    function render_row(rowNum, sA, sB, C, F, rCC, L, aCC, aL, titleStr, insightWav, insightCoh, insightRcc, insightAcc, expectedLag)
        % 1. Waveforms
        ax1 = nexttile((rowNum-1)*4 + 1);
        plot(ax1, t, sA + max(abs(sA))*1.5, 'b', 'LineWidth', 0.8); hold on;
        plot(ax1, t, sB, 'r', 'LineWidth', 0.8);
        xlim(ax1, [-2 2]); % Zoomed for visibility
        title(ax1, titleStr, 'FontWeight', 'bold', 'Interpreter', 'none');
        subtitle(ax1, insightWav, 'Color', '#555', 'Interpreter', 'none');
        grid(ax1, 'on');

        % 2. Coherence
        ax2 = nexttile((rowNum-1)*4 + 2);
        plot(ax2, F, C, 'k', 'LineWidth', 1.5);
        xlim(ax2, [0 20]); ylim(ax2, [0 1.1]);
        if rowNum == 1, title(ax2, 'Coherence (Phase)'); end
        subtitle(ax2, insightCoh, 'Color', '#d62728', 'FontWeight', 'bold');
        grid(ax2, 'on');

        % 3. Raw CC
        ax3 = nexttile((rowNum-1)*4 + 3);
        plot(ax3, L, rCC, 'b', 'LineWidth', 1.5); hold on;
        xline(ax3, 0, 'k--', 'LineWidth', 1);
        if ~isnan(expectedLag), xline(ax3, -expectedLag, 'g-', 'LineWidth', 1.5); end % Target Line
        xlim(ax3, [-maxLagSec*1000 maxLagSec*1000]); ylim(ax3, [-1.1 1.1]);
        if rowNum == 1, title(ax3, 'Raw CC (Waveform)'); end
        subtitle(ax3, insightRcc, 'Color', '#d62728', 'FontWeight', 'bold');
        grid(ax3, 'on');

        % 4. Amp CC
        ax4 = nexttile((rowNum-1)*4 + 4);
        plot(ax4, aL, aCC, 'r', 'LineWidth', 2); hold on;
        xline(ax4, 0, 'k--', 'LineWidth', 1);
        if ~isnan(expectedLag), xline(ax4, -expectedLag, 'g-', 'LineWidth', 1.5); end % Target Line
        xlim(ax4, [-maxLagSec*1000 maxLagSec*1000]); ylim(ax4, [-1.1 1.1]);
        if rowNum == 1, title(ax4, 'Amp CC (Envelope)'); end
        subtitle(ax4, insightAcc, 'Color', '#2ca02c', 'FontWeight', 'bold');
        grid(ax4, 'on');
    end

    % Render the Masterclass Matrix
    render_row(1, S1_A, S1_B, C1, F1, rCC1, L1, aCC1, aL1, ...
        '1. THE CLONE', 'Identical 8Hz Phase & Envelope', ...
        'Peaks at 1.0 @ 8Hz', 'Finds -100ms lag', 'Finds -100ms lag', shift_ms);

    render_row(2, S2_A, S2_B, C2, F2, rCC2, L2, aCC2, aL2, ...
        '2. PHASE SCRAMBLE', '8Hz vs 11Hz | Envelope intact', ...
        'FAILS: Frequencies mismatch', 'FAILS: Waves cannot align', 'SUCCESS: Ignores phase, tracks power', shift_ms);

    render_row(3, S3_A, S3_B, C3, F3, rCC3, L3, aCC3, aL3, ...
        '3. ANTI-CORRELATION', '8Hz Phase Match | Envelope Inverted', ...
        'SUCCESS: Carriers are locked', 'Finds -100ms lag', 'EXACT OPPOSITE: Peaks at -1.0', shift_ms);

    render_row(4, S4_A, S4_B, C4, F4, rCC4, L4, aCC4, aL4, ...
        '4. NULL HYPOTHESIS', 'Independent White Noise', ...
        'Flatline (No false signals)', 'Random variance only', 'Random variance only', shift_ms);

    % Render the Biological Data (No green target line -- expected lag is NaN)
    render_row(5, S5_A, S5_B, C5, F5, rCC5, L5, aCC5, aL5, ...
        ['5. BIOLOGICAL TRUTH (' D.Meta.Session ')'], 'Left POR vs Right DHC', ...
        'Physiological Phase Distribution', 'Broadband Wave Alignment', 'Theta Power Covariance', NaN);

    sgtitle(tlo, 'Theoretical Proofs & Biological Reality: Isolating Connectivity Mathematics (Green = Mathematical Target)', 'FontWeight', 'bold', 'FontSize', 16);
end