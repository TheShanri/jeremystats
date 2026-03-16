import numpy as np
import matplotlib.pyplot as plt

def generate_academic_phase_plots():
    # 1. Setup Signal (Time Domain)
    frequency = 1  # 1 Hz signal
    duration = 4   # 4 seconds
    
    t = np.linspace(0, duration, 1000)
    y = np.sin(2 * np.pi * frequency * t)

    # 2. Simulation Parameters
    total_spikes = 80
    signal_ratio = 0.60
    jitter_width = 0.08 

    n_signal = int(total_spikes * signal_ratio)
    n_noise = total_spikes - n_signal
    cycles = int(duration * frequency)

    # 3. Create Figure
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)
    plt.subplots_adjust(hspace=0.3)

    # --- HELPER: MIXTURE MODEL ---
    def get_mixed_spikes_time(phase_shift_fraction):
        # Background Noise (Uniform)
        noise_spikes = np.random.uniform(0, duration, n_noise)

        # Phase-Locked Signal (Gaussian)
        spikes_per_cycle = n_signal // cycles
        signal_spikes = []
        
        for k in range(cycles):
            center_time = (k + phase_shift_fraction) / frequency
            cycle_batch = np.random.normal(loc=center_time, scale=jitter_width, size=spikes_per_cycle)
            signal_spikes.extend(cycle_batch)
        
        all_spikes = np.concatenate([noise_spikes, signal_spikes])
        all_spikes = all_spikes[(all_spikes >= 0) & (all_spikes <= duration)]
        return np.sort(all_spikes)

    # --- PLOT A: PEAK PREFERENCE ---
    spikes_peak = get_mixed_spikes_time(0.25) # 0.25 = 90 degrees (Peak)
    
    ax1.plot(t, y, color='k', alpha=0.6, linewidth=1.5, label='LFP Signal')
    y_spikes_peak = np.sin(2 * np.pi * frequency * spikes_peak)
    ax1.vlines(spikes_peak, y_spikes_peak - 0.25, y_spikes_peak + 0.25, 
               colors='#D32F2F', linewidth=1.5, alpha=0.8, label='Unit Activity')
    
    # Academic Title 1
    ax1.set_title(r"Stochastic Phase-Locking: Oscillatory Peaks ($\phi \approx \pi/2$)", 
                  fontsize=14, fontweight='bold')
    ax1.set_ylabel("Amplitude (a.u.)")
    ax1.set_ylim(-1.5, 1.5)
    ax1.legend(loc='upper right', frameon=False)

    # --- PLOT B: TROUGH PREFERENCE ---
    spikes_dip = get_mixed_spikes_time(0.75) # 0.75 = 270 degrees (Trough)
    
    ax2.plot(t, y, color='k', alpha=0.6, linewidth=1.5, label='LFP Signal')
    y_spikes_dip = np.sin(2 * np.pi * frequency * spikes_dip)
    ax2.vlines(spikes_dip, y_spikes_dip - 0.25, y_spikes_dip + 0.25, 
               colors='#1976D2', linewidth=1.5, alpha=0.8, label='Unit Activity')
    
    # Academic Title 2
    ax2.set_title(r"Stochastic Phase-Locking: Oscillatory Troughs ($\phi \approx 3\pi/2$)", 
                  fontsize=14, fontweight='bold')
    ax2.set_xlabel("Time (s)")
    ax2.set_ylabel("Amplitude (a.u.)")
    ax2.set_ylim(-1.5, 1.5)
    ax2.legend(loc='upper right', frameon=False)

    # Clean axes
    for ax in [ax1, ax2]:
        ax.spines['top'].set_visible(False)
        ax.spines['right'].set_visible(False)

    # 4. Save and Show
    print("Saving plots to local directory...")
    plt.savefig('phase_preference_plot.png', dpi=300, bbox_inches='tight')
    plt.savefig('phase_preference_plot.pdf', format='pdf', bbox_inches='tight')
    
    plt.show()

if __name__ == "__main__":
    generate_academic_phase_plots()