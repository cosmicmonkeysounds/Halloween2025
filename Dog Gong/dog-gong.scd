// Multi-Input Threshold-Triggered Spatial Sampler
// for Gong Garden installation at Behrooz Mihankhah's Halloween 2025 party
(


    // Boot the server
    s.waitForBoot({

	    // Variables
	    var numInputs = 2;        // number of audio inputs to monitor
	    var numSpeakers = 2;      // number of speakers to output to
	    var threshold = 0.1;      // Amplitude threshold to trigger samples
	    var mediaPath = "media/"; // Path to sample folder
	    var samples, buffers;     // sample files, and their buffers
	    var activeSamples;        // Dictionary to track active samples
	    var speakerPositions;     // 2D positions of speakers

	    // Initialization
	    activeSamples = Dictionary.new;
	    buffers = Dictionary.new;
	    samples = (mediaPath ++ "*").pathMatch;

	    // Load all samples from media folder
	    "Loading samples...".postln;
	    samples.do({ |path|
		    var key = PathName(path).fileName;
		    buffers[key] = Buffer.read(s, path);
		("Lo