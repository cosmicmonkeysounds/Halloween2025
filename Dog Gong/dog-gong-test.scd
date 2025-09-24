/*
Neighbourhood Dog Simulator
for "Dog Gong It" installation
*/

(
// Boot server if needed
s.waitForBoot {
    var dogBuffers, dogPaths;
    var noiseLevel = 0, excitementLevel = 0;
    var fatigue = 0;  // Dogs get tired after prolonged excitement

    // Dog behavior parameters
    var baseDecayRate = 0.05;       // Base rate of excitement decay
    var noiseBoost = 0.15;           // How much noise adds to excitement
    var baseFeedback = 0.12;         // Base pack feedback strength
    var excitementThreshold = 0.25;  // Min excitement to start barking
    var maxDogs = 25;                 // Max simultaneous dogs
    var activeDogs = 0;

    // Timing
    var updateRate = 30;             // Hz for parameter updates
    var barkCheckRate = 8;           // Hz for checking if dogs should bark

    // Load dog samples
    "Looking for dog samples...".postln;
    dogPaths = [];

    // Try current directory first
    if(File.exists("barks")) {
        dogPaths = PathName("barks").files.select({ |f|
            f.extension == "wav" or: { f.extension == "WAV" }
        });
    };

    // If not found, try relative to the script
    if(dogPaths.size == 0 and: { Document.current.notNil }) {
        if(File.exists(Document.current.dir +/+ "barks")) {
            dogPaths = PathName(Document.current.dir +/+ "barks").files.select({ |f|
                f.extension == "wav" or: { f.extension == "WAV" }
            });
        };
    };

    if(dogPaths.size == 0) {
        "WARNING: No WAV files found in 'dogs' folder!".error;
        "".postln;
        "To use dog samples:".postln;
        "1. Create a folder called 'dogs'".postln;
        ("2. Place it in:" + File.getcwd).postln;
        "3. Add WAV files of dog barks to the folder".postln;
        "4. Re-run this code".postln;
        "".postln;
        "RUNNING IN TEST MODE - Using sine beeps instead of dog samples".postln;
        dogBuffers = nil;
    } {
        ("Found" + dogPaths.size + "dog samples:").postln;
        dogPaths.do({ |p| ("  -" + p.fileName).postln; });
        dogBuffers = dogPaths.collect({ |path|
            ("Loading:" + path.fileName).postln;
            Buffer.read(s, path.fullPath);
        });
    };

    s.sync;

    // SynthDef for playing dog barks from samples
    SynthDef(\dogBark, { |out=0, buf=0, pan=0, amp=0.5, rate=1|
        var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rate, doneAction: 2);
        sig = sig * amp;
        Out.ar(out, Pan2.ar(sig, pan));
    }).add;

    // Fallback SynthDef using synthesized "barks"
    SynthDef(\synthBark, { |out=0, pan=0, amp=0.5, freq=400, dur=0.3|
        var sig, env;
        env = EnvGen.kr(Env.perc(0.01, dur), doneAction: 2);
        sig = SinOsc.ar(freq * [1, 1.5, 2, 2.5], 0, [1, 0.6, 0.3, 0.2]).sum;
        sig = sig + (WhiteNoise.ar(0.1) * EnvGen.kr(Env.perc(0.001, 0.05)));
        sig = sig * env * amp * 0.3;
        Out.ar(out, Pan2.ar(sig, pan));
    }).add;

    s.sync;

    // Main dynamics update routine
    fork {
        loop {
            var dt = 1.0 / updateRate;
            var decayRate, effectiveFeedback;

            // Add excitement from noise (only increases, never decreases)
            if(noiseLevel > 0) {
                excitementLevel = (excitementLevel + (noiseLevel * noiseBoost * dt)).min(1.0);
                // Reset fatigue when there's actual noise
                fatigue = (fatigue - (dt * 0.5)).max(0);
            } {
                // Build fatigue when excitement is high but no noise
                if(excitementLevel > 0.5) {
                    fatigue = (fatigue + (dt * 0.1 * excitementLevel)).min(1.0);
                };
            };

            // Calculate decay rate - higher excitement = slower decay
            decayRate = baseDecayRate * (1.0 - (excitementLevel * 0.7));

            // Natural excitement decay
            excitementLevel = (excitementLevel - (decayRate * dt)).max(0);

            // Decay noise level
            noiseLevel = (noiseLevel - (dt * 2.0)).max(0);

            dt.wait;
        }
    };

    // Dog barking logic routine
    fork {
        loop {
            var shouldBark, numDogs, barkProbability;
            var effectiveFeedback;

            // Calculate effective feedback (reduced by fatigue)
            effectiveFeedback = baseFeedback * (1.0 - (fatigue * 0.8));

            // Higher excitement = more feedback, but modulated by fatigue
            effectiveFeedback = effectiveFeedback * (1.0 + (excitementLevel * 2));

            // Calculate bark probability
            barkProbability = excitementLevel * (1.0 - (fatigue * 0.5));

            // Determine if dogs should bark
            if(excitementLevel > excitementThreshold) {
                shouldBark = barkProbability.coin;

                if(shouldBark) {
                    if(dogBuffers.isNil) {
                        // Use synthesized barks if no samples loaded
                        if(activeDogs < maxDogs) {
                            numDogs = (excitementLevel.linlin(0.3, 1, 1, 4).round).asInteger;
                            numDogs = numDogs.min(maxDogs - activeDogs).min(1); // One at a time for synth

                            numDogs.do {
                                var pan = 1.0.rand2;
                                var freq = rrand(200, 800);
                                var amp = excitementLevel.linlin(0, 1, 0.3, 0.9);
                                var dur = rrand(0.2, 0.5);

                                Synth(\synthBark, [
                                    \freq, freq,
                                    \pan, pan,
                                    \amp, amp,
                                    \dur, dur
                                ]);

                                activeDogs = activeDogs + 1;

                                // Add pack excitement (affected by fatigue)
                                excitementLevel = (excitementLevel + (effectiveFeedback * rrand(0.5, 1.0))).min(1.0);

                                // Schedule dog count decrease based on actual duration
                                fork {
                                    dur.wait;
                                    activeDogs = activeDogs - 1;
                                };

                                rrand(0.05, 0.15).wait;
                            };
                        };
                    } {
                        // Use real dog samples
                        if(activeDogs < maxDogs) {
                            numDogs = (excitementLevel.linlin(0.3, 1, 1, 4).round).asInteger;
                            numDogs = numDogs.min(maxDogs - activeDogs);

                            numDogs.do {
                                var buffer = dogBuffers.choose;
                                var pan = 1.0.rand2;
                                var rate = rrand(0.85, 1.15);  // Pitch variation
                                var amp = excitementLevel.linlin(0, 1, 0.4, 1.0);
                                var duration = buffer.duration / rate;

                                Synth(\dogBark, [
                                    \buf, buffer,
                                    \pan, pan,
                                    \rate, rate,
                                    \amp, amp
                                ]);

                                activeDogs = activeDogs + 1;

                                // Add pack excitement (affected by fatigue)
                                excitementLevel = (excitementLevel + (effectiveFeedback * rrand(0.5, 1.0))).min(1.0);

                                // Schedule dog count decrease based on actual sample duration
                                fork {
                                    duration.wait;
                                    activeDogs = activeDogs - 1;
                                };

                                rrand(0.05, 0.15).wait;
                            };
                        };
                    };
                };
            };

            (1.0 / barkCheckRate).wait;
        }
    };

    // Visual feedback routine
    fork {
        loop {
            var barChar = "|";
            var excitementBar = barChar ! (excitementLevel * 30).round;
            var noiseBar = barChar ! (noiseLevel * 3.33).round;
            var fatigueBar = barChar ! (fatigue * 20).round;

            "\n=== Dog Neighbourhood Simulator ===".postln;
            ("Noise Level [0-9]:" + noiseLevel.round(0.1) + noiseBar.join).postln;
            ("Excitement:" + excitementLevel.round(0.01) + excitementBar.join).postln;
            ("Fatigue:" + fatigue.round(0.02) + fatigueBar.join).postln;
            ("Active Dogs:" + activeDogs + "/" + maxDogs).postln;

            if(excitementLevel > 0.5 and: { fatigue > 0.5 }) {
                "  [Dogs getting tired - feedback weakening]".postln;
            };

            "".postln;
            "Keys: 0-9 = add noise burst, ESC = quit".postln;

            0.1.wait;
        }
    };

    // Keyboard input
    w = Window("Dog Simulator Control", Rect(100, 100, 400, 200)).front;
    w.view.keyDownAction = { |view, char, modifiers, unicode, keycode|
        case
        // Number keys 0-9 for noise level
        { char.isDecDigit } {
            // Noise ADDS to excitement, doesn't set level
            var noiseBurst = char.digit;
            noiseLevel = (noiseLevel + noiseBurst).min(9);
            ("Noise burst added:" + noiseBurst + "-> total noise:" + noiseLevel).postln;

            // Immediate excitement boost from sudden noise
            excitementLevel = (excitementLevel + (noiseBurst * 0.02)).min(1.0);
        }

        // ESC to quit
        { keycode == 27 } { w.close; };
    };

    w.onClose = {
        "Dog Simulator stopped".postln;
    };

    "".postln;
    "=== Dog Neighbourhood Simulator Started ===".postln;
    "Use number keys 0-9 to ADD noise bursts".postln;
    "Watch how the pack dynamics evolve!".postln;
    "".postln;
    "Behaviors:".postln;
    "- Noise only increases excitement, never decreases it".postln;
    "- Higher excitement = slower natural decay".postln;
    "- Higher excitement = stronger pack feedback".postln;
    "- Prolonged excitement without noise = fatigue builds".postln;
    "- Fatigue weakens the pack feedback effect".postln;
    "".postln;
};
);