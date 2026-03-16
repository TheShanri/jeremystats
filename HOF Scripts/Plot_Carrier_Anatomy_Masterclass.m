function Plot_Coherence_Modulation_Masterclass()
% PLOT_COHERENCE_MODULATION_MASTERCLASS
% Isolates the effects of Amplitude Modulation (AM) and SNR on Phase Coherence.

    fprintf('\n=======================================================\n');
    fprintf('COHERENCE & AMPLITUDE MODULATION MASTERCLASS\n');
    fprintf('=======================================================\n');

    % 1. Universal Grid
    fs = 1000; 
    t = linspace(0, 20, 20 * fs); % 20 seconds for high frequency resolution
    
    % Coherence Parameters 
    % A 2-second window yields exactly 0.5 Hz resolution. 
    % This is critical to explicitly reveal the 0.5 Hz sidebands.
    wsize = 2 * fs; 
    noverlap = wsize / 2; 
    nfft = wsize; 
    
    noise_floor = 0.5;

    % 2. Mathematical Components
    car_8Hz = sin(2*pi*8*t);
    env_dc  = 2 * ones(size(t));         % Pure flat power
    env_2Hz = sin(2*pi*2*t) + 2;         % Fast 2 Hz envelope
    env_slow = sin(2*pi*0.5*t) + 2;      % Slow 0.5 Hz envelope
    env_inv  = -sin(2*pi*0.5*t) + 2;     % Inverted 0.5 Hz envelope

    % Pair 1: Pure Unmodulated Carriers
    % Theory: No modulation. Just an 8 Hz wave.
    % Expectation: A single, infinitely sharp spike exactly at 8 Hz.
    S1_A = env_dc .* car_8Hz + noise_floor * randn(size(t));
    S1_B = env_dc .* car_8Hz + noise_floor * randn(size(t));

    % Pair 2: Fast Modulation (The Wide Sidebands)
    % Theory: 8 Hz carrier modulated by a fast 2 Hz envelope.
    % Expectation: The math dictates new frequencies at 6 Hz (8-2) and 10 Hz (8+2). 
    S2_A = env_2Hz .* car_8Hz + noise_floor * randn(size(t));
    S2_B = env_2Hz .* car_8Hz + noise_floor * randn(size(t));

    % Pair 3: Slow Modulation (The Sideband Shoulders)
    % Theory: 8 Hz carrier modulated by a 0.5 Hz envelope (Standard physiological theta).
    % Expectation: Sidebands emerge at 7.5 Hz and 8.5 Hz, creating wide "shoulders" around 8 Hz.
    S3_A = env_slow .* car_8Hz + noise_floor * randn(size(t));
    S3_B = env_slow .* car_8Hz + noise_floor * randn(size(t));

    % Pair 4: Anti-Correlation (The Sideband Destruction)
    % Theory: The envelopes are inverted. When A is loud, B is quiet. 
    % Expectation: They never share high SNR simultaneously. The 7.5 Hz and 8.5 Hz 
    % sideband coherence collapses, creating the sharp dips you observed.
    S4_A = env_slow .* car_8Hz + noise_floor * randn(size(t));
    S4_B = env_inv  .* car_8Hz + noise_floor * randn(size(t));

    % Pair 5: Phase Scramble (The True Baseline)
    % Theory: 8 Hz versus 9.5 Hz. Frequencies do not match.
    % Expectation: Total coherence failure.
    S5_A = env_dc .* car_8Hz + noise_floor * randn(size(t));
    S5_B = env_dc .* sin(2*pi*9.5*t) + noise_floor * randn(size(t));

    % 3. Compute Metrics
    function [C, F] = get_coh(sA, sB)
        [C, F] = mscohere(sA, sB, hanning(wsize), noverlap, nfft, fs);
    end

    [C1, F1] = get_coh(S1_A, S1_B);
    [C2, F2] = get_coh(S2_A, S2_B);
    [C3, F3] = get_coh(S3_A, S3_B);
    [C4, F4] = get_coh(S4_A, S4_B);
    [C5, F5] = get_coh(S5_A, S5_B);

    % 4. Visualization
    hFig = figure('Name', 'Coherence & Amplitude Modulation', 'Color', 'w', 'Position', [50, 50, 1400, 1000]);
    tlo = tiledlayout(5, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    function render_row(rowNum, sA, sB, C, F, titleStr, descStr, cohStr)
        % Waveform Plot
        ax1 = nexttile((rowNum-1)*2 + 1);
        plot(ax1, t, sA + 5, 'b', 'LineWidth', 0.8); hold on;
        plot(ax1, t, sB, 'r', 'LineWidth', 0.8);
        xlim(ax1, [0 4]); ylim(ax1, [-4 10]);
        title(ax1, titleStr, 'FontWeight', 'bold');
        subtitle(ax1, descStr, 'Color', '#555');
        grid(ax1, 'on');

        % Coherence Plot (Zoomed strictly to 2-14 Hz)
        ax2 = nexttile((rowNum-1)*2 + 2);
        plot(ax2, F, C, 'k', 'LineWidth', 2);
        xline(ax2, 8, 'g--', 'LineWidth', 1); % Mark the 8Hz carrier
        xlim(ax2, [2 14]); ylim(ax2, [0 1.1]);
        if rowNum == 1, title(ax2, 'Magnitude-Squared Coherence'); end
        subtitle(ax2, cohStr, 'Color', '#d62728', 'FontWeight', 'bold');
        grid(ax2, 'on');
    end

    render_row(1, S1_A, S1_B, C1, F1, '1. PURE CARRIERS', 'Unmodulated 8 Hz', 'Single isolated spike at 8 Hz');
    render_row(2, S2_A, S2_B, C2, F2, '2. FAST MODULATION', '8 Hz Carrier | 2 Hz Envelope', 'Three distinct peaks: 6 Hz, 8 Hz, 10 Hz');
    render_row(3, S3_A, S3_B, C3, F3, '3. SLOW MODULATION', '8 Hz Carrier | 0.5 Hz Envelope', 'Shoulders emerge at 7.5 Hz and 8.5 Hz');
    render_row(4, S4_A, S4_B, C4, F4, '4. ANTI-CORRELATION', '8 Hz Carrier | Inverted 0.5 Hz Envelope', 'Alternating SNR destroys sidebands -> Sharp Dips');
    render_row(5, S5_A, S5_B, C5, F5, '5. FREQUENCY MISMATCH', '8 Hz vs 9.5 Hz', 'Total Phase Failure');

    sgtitle(tlo, 'The Physics of Coherence: Amplitude Modulation & Spectral Sidebands', 'FontWeight', 'bold', 'FontSize', 16);
end