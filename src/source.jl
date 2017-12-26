function source(stim::T1, τ::Real)
    τ<20e-9 && error("τ must be at least 20ns")
    #renaming for convinience
    awgXY = stim.awgXY
    awgRead = stim.awgRead
    awgMarker = stim.awgMarker
    πPulse = stim.πPulse
    readoutPulse = stim.readoutPulse

    #computing delays and loading delays
    decay_num_20ns = Int(div(stim.decay_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    end_num_20ns = Int(div(stim.end_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    read_fudge = 8  #there is a delay in output when outputting directly from the AWG, vs outputting from FG and amplitude modulating it
    xy_fudge = 2 #there is a delay in output when outputting from the fast AWG compared the slow AWG
    read_T1_delay = DelayPulse(τ + πPulse.duration, awgRead[SampleRate], name = "read_T1_delay")
    marker_T1_delay = DelayPulse(τ + πPulse.duration, awgMarker[SampleRate], name = "marker_T1_delay")
    τ_delay = DelayPulse(τ, awgXY[SampleRate], name = "τ_delay") #note: can't do τ equal zero, that's an edge case
    load_pulse(awgXY, τ_delay, "τ_delay")
    load_pulse(awgRead, read_T1_delay, "read_T1_delay")
    load_pulse(awgMarker, marker_T1_delay, "marker_T1_delay")
    readoutPulse_delay_id = find_wav_id(awgXY, "readoutPulse_delay")
    markerPulseID = find_wav_id(awgMarker, "Markers_Voltage=1.5")
    delay_id_XY = find_wav_id(awgXY, "20ns_delay")
    delay_id_Read = find_wav_id(awgRead, "20ns_delay")
    delay_id_Marker = find_wav_id(awgMarker, "20ns_delay")

    #prepping AWG for sourcing: stopping AWG in case it wasn't stopped before, flushing
    #queue to reset it, setting the PXI_line to off
    awg_stop(awgXY, stim.IQ_XY_chs...)
    awg_stop(awgRead, stim.IQ_readout_chs...)
    awg_stop(awgMarker, stim.markerCh)
    @KSerror_handler SD_Module_PXItriggerWrite(awgMarker.ID, stim.PXI_line, 1) #turning line off in case it was on before
    queue_flush.(awgXY, stim.IQ_XY_chs)
    queue_flush.(awgRead, stim.IQ_readout_chs)
    queue_flush(awgMarker, stim.markerCh)
    sleep(0.001)

    #awgXY queueing
    queue_waveform.(awgXY, stim.IQ_XY_chs, πPulse.envelope, :External, delay = xy_fudge)
    queue_waveform.(awgXY, stim.IQ_XY_chs, τ_delay.waveform, :Auto)
    queue_waveform.(awgXY, stim.IQ_XY_chs, readoutPulse_delay_id, :Auto)
    queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY,  :Auto, repetitions = decay_num_20ns - Int(xy_fudge/2))
    # queue_waveform.(awgXY, stim.IQ_XY_chs, readoutPulse_delay_id,  :Auto)
    # queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY,  :Auto, repetitions = end_num_20ns - Int(xy_fudge/2))

    #awgRead queueing
    read_I = stim.IQ_readout_chs[1]
    read_Q = stim.IQ_readout_chs[2]
    queue_waveform.(awgRead, stim.IQ_readout_chs, read_T1_delay.waveform, :External, delay = read_fudge)
    queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :Auto)
    queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform, :Auto)
    queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = decay_num_20ns - Int(read_fudge/2))
    # queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :Auto)
    # queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform,  :Auto)
    # queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read,  :Auto, repetitions = end_num_20ns - Int(read_fudge/2))

    #awgMarker queueing
    queue_waveform(awgMarker, stim.markerCh, marker_T1_delay.waveform, :External)
    queue_waveform(awgMarker, stim.markerCh, markerPulseID, :Auto)
    queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = decay_num_20ns)
    # queue_waveform(awgMarker, stim.markerCh, markerPulseID, :Auto)
    # queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = end_num_20ns)

    #Start AWGs
    awg_start(awgRead, stim.IQ_readout_chs...)
    awg_start(awgXY, stim.IQ_XY_chs...)
    awg_start(awgMarker, stim.markerCh)
    nothing
end

function source(stim::Rabi, t::Real)
    t<20e-9 && error("t must be at least 20ns")
    (rem(round(t/1e-9), 10) != 0.0) && error("XY pulse length must be in mutiple of 10ns")
    #renaming for convinience
    awgXY = stim.awgXY
    awgRead = stim.awgRead
    awgMarker = stim.awgMarker
    XYPulse = stim.XYPulse
    readoutPulse = stim.readoutPulse

    #complete XYPulse envelope and load it
    sample_rate = awgXY[SampleRate]
    XYPulse.duration = t
    env = make_CosEnvelope(t, sample_rate)
    XYPulse.envelope = Waveform(env, "Rabi_XYPulse")
    load_pulse(awgXY, XYPulse, "Rabi_XYPulse")

    #computing delays and loading delays
    decay_num_20ns = Int(div(stim.decay_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    end_num_20ns = Int(div(stim.end_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    read_fudge = 8  #channels 1 and 3 on awg in slot 3 are somewhat unsynced, this is a fudge factor--> might depend on whatever awgs and whatever channels
    xy_fudge = 2 #there is a delay in output when outputting from the fast AWG compared the slow AWG
    read_Rabi_delay = DelayPulse(t, awgRead[SampleRate], name = "read_Rabi_delay")
    marker_Rabi_delay = DelayPulse(t, awgMarker[SampleRate], name = "marker_Rabi_delay")
    load_pulse(awgRead, read_Rabi_delay, "read_Rabi_delay")
    load_pulse(awgMarker, marker_Rabi_delay, "marker_Rabi_delay")
    readoutPulse_delay_id = find_wav_id(awgXY, "readoutPulse_delay")
    markerPulseID = find_wav_id(awgMarker, "Markers_Voltage=1.5")
    delay_id_XY = find_wav_id(awgXY, "20ns_delay")
    delay_id_Read = find_wav_id(awgRead, "20ns_delay")
    delay_id_Marker = find_wav_id(awgMarker, "20ns_delay")

    #prepping AWG for sourcing: stopping AWG in case it wasn't stopped before, flushing
    #queue to reset it, setting the PXI_line to off
    awg_stop(awgXY, stim.IQ_XY_chs...)
    awg_stop(awgRead, stim.IQ_readout_chs...)
    awg_stop(awgMarker, stim.markerCh)
    @KSerror_handler SD_Module_PXItriggerWrite(awgMarker.ID, stim.PXI_line, 1)
    queue_flush.(awgXY, stim.IQ_XY_chs)
    queue_flush.(awgRead, stim.IQ_readout_chs)
    queue_flush(awgMarker, stim.markerCh)
    sleep(0.001)

    #awgXY queueing
    queue_waveform.(awgXY, stim.IQ_XY_chs, XYPulse.envelope, :External, delay = xy_fudge)
    queue_waveform.(awgXY, stim.IQ_XY_chs, readoutPulse_delay_id, :Auto)
    queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY, :Auto, repetitions = decay_num_20ns - Int(xy_fudge/2))
    # queue_waveform.(awgXY, stim.IQ_XY_chs, readoutPulse_delay_id, :Auto)
    # queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY, :Auto, repetitions = end_num_20ns - Int(xy_fudge/2))

    #awgRead queueing
    read_I = stim.IQ_readout_chs[1]
    read_Q = stim.IQ_readout_chs[2]
    queue_waveform.(awgRead, stim.IQ_readout_chs, read_Rabi_delay.waveform, :External, delay = read_fudge)
    queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :Auto)
    queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform, :Auto)
    queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = decay_num_20ns - Int(read_fudge/2))
    # queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :Auto)
    # queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform, :Auto)
    # queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = end_num_20ns - Int(read_fudge/2))

    #awgMarker queueing
    queue_waveform(awgMarker, stim.markerCh, marker_Rabi_delay.waveform, :External)
    queue_waveform(awgMarker, stim.markerCh, markerPulseID,  :Auto)
    queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = decay_num_20ns)
    # queue_waveform.(awgMarker, stim.markerCh, markerPulseID, :Auto)
    # queue_waveform.(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = end_num_20ns)

    #Start AWGs
    awg_start(awgRead, stim.IQ_readout_chs...)
    awg_start(awgXY, stim.IQ_XY_chs...)
    awg_start(awgMarker, stim.markerCh)
    nothing
end

function source(stim::Ramsey, τ::Real)
    τ<20e-9 && error("τ must be at least 20ns")
    awgXY = stim.awgXY
    awgRead = stim.awgRead
    awgMarker = stim.awgMarker
    π_2Pulse = stim.π_2Pulse
    readoutPulse = stim.readoutPulse

    #computing delays and loading delays
    decay_num_20ns = Int(div(stim.decay_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    end_num_20ns = Int(div(stim.end_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    read_fudge = 8  #channels 1 and 3 on awg in slot 3 are somewhat unsynced, this is a fudge factor--> might depend on whatever awgs and whatever channels
    xy_fudge = 2 #there is a delay in output when outputting from the fast AWG compared the slow AWG
    read_Ramsey_delay = DelayPulse(τ + 2*π_2Pulse.duration, awgRead[SampleRate], name = "read_Ramsey_delay")
    marker_Ramsey_delay = DelayPulse(τ + 2*π_2Pulse.duration, awgMarker[SampleRate], name = "marker_Ramsey_delay")
    τ_delay = DelayPulse(τ, awgXY[SampleRate], name = "τ_delay") #note: can't do τ equal zero, that's an edge case
    load_pulse(awgXY, τ_delay, "τ_delay")
    load_pulse(awgRead, read_Ramsey_delay, "read_Ramsey_delay")
    load_pulse(awgMarker, marker_Ramsey_delay, "marker_Ramsey_delay")
    readoutPulse_delay_id = find_wav_id(awgXY, "readoutPulse_delay")
    markerPulseID = find_wav_id(awgMarker, "Markers_Voltage=1.5")
    delay_id_XY = find_wav_id(awgXY, "20ns_delay")
    delay_id_Read = find_wav_id(awgRead, "20ns_delay")
    delay_id_Marker = find_wav_id(awgMarker, "20ns_delay")

    #prepping AWG for sourcing: stopping AWG in case it wasn't stopped before, flushing
    #queue to reset it, setting the PXI_line to off
    awg_stop(awgXY, stim.IQ_XY_chs...)
    awg_stop(awgRead, stim.IQ_readout_chs...)
    awg_stop(awgMarker, stim.markerCh)
    @KSerror_handler SD_Module_PXItriggerWrite(awgMarker.ID, stim.PXI_line, 1)
    queue_flush.(awgXY, stim.IQ_XY_chs)
    queue_flush.(awgRead, stim.IQ_readout_chs)
    queue_flush(awgMarker, stim.markerCh)
    sleep(0.001)

    #awgXY queueing
    queue_waveform.(awgXY, stim.IQ_XY_chs, π_2Pulse.envelope, :External, delay = xy_fudge)
    queue_waveform.(awgXY, stim.IQ_XY_chs, τ_delay.waveform, :Auto)
    queue_waveform.(awgXY, stim.IQ_XY_chs, π_2Pulse.envelope, :Auto)
    queue_waveform.(awgXY, stim.IQ_XY_chs, readoutPulse_delay_id, :Auto)
    queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY, :Auto, repetitions = decay_num_20ns - Int(xy_fudge/2))
    # queue_waveform.(awgXY, stim.IQ_XY_chs, readoutPulse_delay_id, :Auto)
    # queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY, :Auto, repetitions = end_num_20ns - Int(xy_fudge/2) )

    #awgRead queueing
    read_I = stim.IQ_readout_chs[1]
    read_Q = stim.IQ_readout_chs[2]
    queue_waveform.(awgRead, stim.IQ_readout_chs, read_Ramsey_delay.waveform, :External, delay = read_fudge)
    queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :Auto)
    queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform, :Auto)
    queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = decay_num_20ns -Int(read_fudge/2))
    # queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :Auto)
    # queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform, :Auto)
    # queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = end_num_20ns-Int(read_fudge/2))

    #awgMarker queueing
    queue_waveform(awgMarker, stim.markerCh, marker_Ramsey_delay.waveform, :External)
    queue_waveform(awgMarker, stim.markerCh, markerPulseID, :Auto)
    queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = decay_num_20ns)
    # queue_waveform(awgMarker, stim.markerCh, markerPulseID, :Auto)
    # queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = end_num_20ns)

    #Start AWGs
    awg_start(awgRead, stim.IQ_readout_chs...)
    awg_start(awgXY, stim.IQ_XY_chs...)
    awg_start(awgMarker, stim.markerCh)
    nothing
end

function source(stim::StarkShift, t::Real)
    t<20e-9 && error("t must be at least 20ns")
    (rem(round(t/1e-9), 10) != 0.0) && error("drive pulse length must be in mutiple of 10ns")
    #renaming for convinience
    awgXY = stim.awgXY
    awgRead = stim.awgRead
    awgMarker = stim.awgMarker
    πPulse = stim.πPulse
    readoutPulse = stim.readoutPulse

    #make drive pulse and load it
    drivePulse = DigitalPulse(readoutPulse.IF_freq, readoutPulse.amplitude, t, RectEnvelope,
                              awgRead[SampleRate], IF_phase = readoutPulse.IF_phase, name = "Readout Drive Pulse")
    load_pulse(awgXY, drivePulse, "Readout Drive Pulse")

    #computing delays and loading delays
    ringdown_num_20ns = Int(div(stim.ringdown_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    end_num_20ns = Int(div(stim.end_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    read_fudge = 8  #channels 1 and 3 on awg in slot 3 are somewhat unsynced, this is a fudge factor--> might depend on whatever awgs and whatever channels
    xy_fudge = 2 #there is a delay in output when outputting from the fast AWG compared the slow AWG
    xy_stark_delay = DelayPulse(t, awgXY[SampleRate], name = "xy_stark_delay")
    read_stark_delay = DelayPulse(πPulse.duration, awgRead[SampleRate], name = "read_stark_delay")
    marker_stark_delay = DelayPulse(t + πPulse.duration, awgMarker[SampleRate], name = "marker_stark_delay")
    load_pulse(awgXY, xy_stark_delay, "xy_stark_delay")
    load_pulse(awgRead, read_stark_delay, "read_stark_delay")
    load_pulse(awgMarker, marker_stark_delay, "marker_stark_delay")
    readoutPulse_delay_id = find_wav_id(awgXY, "readoutPulse_delay")
    markerPulseID = find_wav_id(awgMarker, "Markers_Voltage=1.5")
    delay_id_XY = find_wav_id(awgXY, "20ns_delay")
    delay_id_Read = find_wav_id(awgRead, "20ns_delay")
    delay_id_Marker = find_wav_id(awgMarker, "20ns_delay")

    #prepping AWG for sourcing: stopping AWG in case it wasn't stopped before, flushing
    #queue to reset it, setting the PXI_line to off
    awg_stop(awgXY, stim.IQ_XY_chs...)
    awg_stop(awgRead, stim.IQ_readout_chs...)
    awg_stop(awgMarker, stim.markerCh)
    @KSerror_handler SD_Module_PXItriggerWrite(awgMarker.ID, stim.PXI_line, 1)
    queue_flush.(awgXY, stim.IQ_XY_chs)
    queue_flush.(awgRead, stim.IQ_readout_chs)
    queue_flush(awgMarker, stim.markerCh)
    sleep(0.001)

    #awgXY queueing
    queue_waveform.(awgXY, stim.IQ_XY_chs, xy_stark_delay.waveform, :External, delay = xy_fudge)
    queue_waveform.(awgXY, stim.IQ_XY_chs, πPulse.envelope, :Auto)
    queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY, :Auto, repetitions = ringdown_num_20ns)
    queue_waveform.(awgXY, stim.IQ_XY_chs, readoutPulse_delay_id, :Auto)
    queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY, :Auto, repetitions = end_num_20ns - Int(xy_fudge/2))

    #awgRead queueing
    read_I = stim.IQ_readout_chs[1]
    read_Q = stim.IQ_readout_chs[2]
    queue_waveform(awgRead, read_I, drivePulse.I_waveform, :External)
    queue_waveform(awgRead, read_Q, drivePulse.Q_waveform, :External)
    queue_waveform.(awgRead, stim.IQ_readout_chs, read_stark_delay.waveform, :Auto)
    queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = ringdown_num_20ns)
    queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :Auto)
    queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform, :Auto)
    queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = end_num_20ns - Int(read_fudge/2))

    #awgMarker queueing
    queue_waveform(awgMarker, stim.markerCh, marker_stark_delay.waveform, :External)
    queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = ringdown_num_20ns)
    queue_waveform(awgMarker, stim.markerCh, markerPulseID,  :Auto)
    queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = end_num_20ns)

    #Start AWGs
    awg_start(awgRead, stim.IQ_readout_chs...)
    awg_start(awgXY, stim.IQ_XY_chs...)
    awg_start(awgMarker, stim.markerCh)
    nothing
end

function source(stim::CPecho)
    #renaming for convinience
    awgXY = stim.awgXY
    awgRead = stim.awgRead
    awgMarker = stim.awgMarker
    πPulse = stim.πPulse
    π_2Pulse = stim.π_2Pulse
    readoutPulse = stim.readoutPulse
    nπ = stim.n_π
    τ = stim.τ

    #making XY pulse train as one big waveform and loading it
    π_2_delay = τ/(2*nπ)
    π_delay = τ/(nπ)
    π_2_delay_samples = Int(round(π_2_delay*awgXY[SampleRate]))
    π_delay_samples = Int(round(π_delay*awgXY[SampleRate]))

    CPecho_pulse_sequence =
        vcat(π_2Pulse.envelope.waveformValues, zeros(π_2_delay_samples),
             repeat(vcat(πPulse.envelope.waveformValues, zeros(π_delay_samples)), outer = nπ-1),
             πPulse.envelope.waveformValues, zeros(π_2_delay_samples), π_2Pulse.envelope.waveformValues)
    CP_waveform = Waveform(CPecho_pulse_sequence, "CPecho_pulse_sequence")
    load_waveform(awgXY, CP_waveform, find_wav_id(awgXY, "CPecho_pulse_sequence"))
    CP_duration = size(CPecho_pulse_sequence)/awgXY[SampleRate]

    #computing delays and loading delays
    decay_num_20ns = Int(div(stim.decay_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    end_num_20ns = Int(div(stim.end_delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    read_fudge = 8  #channels 1 and 3 on awg in slot 3 are somewhat unsynced, this is a fudge factor--> might depend on whatever awgs and whatever channels
    xy_fudge = 2 #there is a delay in output when outputting from the fast AWG compared the slow AWG
    read_CPecho_delay = DelayPulse(CP_duration, awgXY[SampleRate], "read_CPecho_delay")
    marker_CPecho_delay = DelayPulse(CP_duration, awgMarker[SampleRate], "marker_CPecho_delay")
    load_pulse(awgRead, read_CPecho_delay, "read_CPecho_delay")
    load_pulse(awgMarker, marker_CPecho_delay, "marker_CPecho_delay")
    readoutPulse_delay_id = find_wav_id(awgXY, "readoutPulse_delay")
    markerPulseID = find_wav_id(awgMarker, "Markers_Voltage=1.5")
    delay_id_XY = find_wav_id(awgXY, "20ns_delay")
    delay_id_Read = find_wav_id(awgRead, "20ns_delay")
    delay_id_Marker = find_wav_id(awgMarker, "20ns_delay")

    #prepping AWG for sourcing: stopping AWG in case it wasn't stopped before, flushing
    #queue to reset it, setting the PXI_line to off
    awg_stop(awgXY, stim.IQ_XY_chs...)
    awg_stop(awgRead, stim.IQ_readout_chs...)
    awg_stop(awgMarker, stim.markerCh)
    @KSerror_handler SD_Module_PXItriggerWrite(awgMarker.ID, stim.PXI_line, 1)
    queue_flush.(awgXY, stim.IQ_XY_chs)
    queue_flush.(awgRead, stim.IQ_readout_chs)
    queue_flush(awgMarker, stim.markerCh)
    sleep(0.001)

    #awgXY queueing
    queue_waveform.(awgXY, stim.IQ_XY_chs, CP_waveform, :External, delay = xy_fudge)
    queue_waveform.(awgXY, stim.IQ_XY_chs, readoutPulse_delay_id, :Auto)
    queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY, :Auto, repetitions = decay_num_20ns - Int(xy_fudge/2))
    # queue_waveform.(awgXY, stim.IQ_XY_chs, readoutPulse_delay_id, :Auto)
    # queue_waveform.(awgXY, stim.IQ_XY_chs, delay_id_XY, :Auto, repetitions = end_num_20ns - Int(xy_fudge/2) )

    #awgRead queueing
    read_I = stim.IQ_readout_chs[1]
    read_Q = stim.IQ_readout_chs[2]
    queue_waveform.(awgRead, stim.IQ_readout_chs, read_CPecho_delay.waveform, :External, delay = read_fudge)
    queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :Auto)
    queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform, :Auto)
    queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = decay_num_20ns -Int(read_fudge/2))
    # queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :Auto)
    # queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform, :Auto)
    # queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = end_num_20ns-Int(read_fudge/2))

    #awgMarker queueing
    queue_waveform(awgMarker, stim.markerCh, marker_CPecho_delay.waveform, :External)
    queue_waveform(awgMarker, stim.markerCh, markerPulseID, :Auto)
    queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = decay_num_20ns)
    # queue_waveform(awgMarker, stim.markerCh, markerPulseID, :Auto)
    # queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = end_num_20ns)

    #Start AWGs
    awg_start(awgRead, stim.IQ_readout_chs...)
    awg_start(awgXY, stim.IQ_XY_chs...)
    awg_start(awgMarker, stim.markerCh)
    nothing
end

function source(CPecho_n, n::Integer)
    CPecho_n.CPstim.n_π = n
    source(CPecho_n.CPstim)
    nothing
end

function source(CPecho_τ, τ::Real)
    CPecho_τ.CPstim.τ = τ
    source(CPecho_τ.CPstim)
    nothing
end

function source(stim::ReadoutReference)
    awgRead = stim.awgRead
    awgMarker = stim.awgMarker
    readoutPulse = stim.readoutPulse

    #computing delays and loading delays
    decay_num_20ns = Int(div(stim.delay + 1e-9,20e-9)) #added extra 1e-9 because of floating point issues
    read_fudge = 8  #there is a delay in output when outputting directly from the AWG, vs outputting from FG and amplitude modulating it
    markerPulseID = find_wav_id(awgMarker, "Markers_Voltage=1.5")
    delay_id_Read = find_wav_id(awgRead, "20ns_delay")
    delay_id_Marker = find_wav_id(awgMarker, "20ns_delay")

    awg_stop(awgRead, stim.IQ_readout_chs...)
    awg_stop(awgMarker, stim.markerCh)
    queue_flush.(awgRead, stim.IQ_readout_chs)
    queue_flush(awgMarker, stim.markerCh)
    sleep(0.001)

    #awgRead queueing
    read_I = stim.IQ_readout_chs[1]
    read_Q = stim.IQ_readout_chs[2]
    queue_waveform(awgRead, read_I, readoutPulse.I_waveform, :External, delay = read_fudge)
    queue_waveform(awgRead, read_Q, readoutPulse.Q_waveform, :External, delay = read_fudge)
    queue_waveform.(awgRead, stim.IQ_readout_chs, delay_id_Read, :Auto, repetitions = decay_num_20ns - Int(read_fudge/2))

    #awgMarker queueing
    queue_waveform(awgMarker, stim.markerCh, markerPulseID, :External)
    queue_waveform(awgMarker, stim.markerCh, delay_id_Marker, :Auto, repetitions = decay_num_20ns)

    #Start AWGs
    awg_start(awgRead, stim.IQ_readout_chs...)
    awg_start(awgMarker, stim.markerCh)
    nothing
end
