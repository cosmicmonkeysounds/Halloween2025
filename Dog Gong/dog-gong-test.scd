/*
Neighbourhood Dog Simulator
for "Dog Gong It" installation
*/

(
// Boot server if needed
s.waitForBoot {
    var dogBuffers, dogPaths;
    var noiseLevel = 0;

    // State variables with velocities for spring dynamics
    var excitementLevel = 0, excitementVelocity = 0, excitementTarget = 0;
    var fatigueLevel = 0, fatigueVelocity = 0, fatigueTarget = 0;

    // Spring parameters for excitement
    var excRisingFreq = 2.0, excRisingDamp = 0.3;   // Faster rise
    var excFallingFreq = 0.5, excFallingDamp = 0.7;  // Slower fall

    // Spring parameters for fatigue
    var fatRisingFreq = 0.3, fatRisingDamp = 0.8;    // Slow fatigue buildup
    var fatFallingFreq = 0.8, fatFallingDamp = 0.4;  // Moderate recovery

    // Dog behavior parameters
    var noiseBoost = 0.08;           // How much noise adds to excitement target
    var baseFeedback = 0.1;          // Base pack feedback strength
    var excitementThreshold = 0.25;  // Min excitement to start barking
	var maxDogs = 25;                 // Max simultaneous dogs
    var activeDogs = 0;

    // Timing
    var updateRate = 60;             // Hz for spring updates
    var barkCheckRate = 8;           // Hz for checking if dogs should bark

    // Load dog samples from "barks" folder
    "Looking for dog samples in 'barks' folder...".postln;
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
        "WARNING: No WAV files found in 'barks' folder!".error;
        "".postln;
        "To use dog samples:".postln;
        "1. Create a folder called 'barks'".postln;
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

    // Spring dynamics update routine
    fork {
        loop {
            var dt = 1.0 / updateRate;
            var excSpringFreq, excSpringDamp, excForce, excAccel;
            var fatSpringFreq, fatSpringDamp, fatForce, fatAccel;
            var k, c;
            var excIsRising, fatIsRising;

            // === EXCITEMENT DYNAMICS ===
            // Calculate excitement target (only increases from noise, pack feedback adds directly to level)
            if(noiseLevel > 0) {
                excitementTarget = (excitementTarget + (noiseLevel * noiseBoost * dt)).min(0.95);
            } {
                // Natural target decay when no noise
                excitementTarget = (excitementTarget - (dt * 0.2)).max(0);
            };

            // Higher excitement = higher minimum target (self-sustaining)
            excitementTarget = excitementTarget.max(excitementLevel * 0.3);

            // Determine if excitement is rising or falling
            excIsRising = excitementTarget > excitementLevel;

            // Select spring parameters for excitement
            if(excIsRising) {
                excSpringFreq = excRisingFreq;
                excSpringDamp = excRisingDamp;
            } {
                // Slower fall at higher excitement levels
                excSpringFreq = excFallingFreq * (1.0 - (excitementLevel * 0.5));
                excSpringDamp = excFallingDamp;
            };

            // Calculate spring force for excitement
            k = (2pi * excSpringFreq).squared;
            c = 2 * excSpringDamp * 2pi * excSpringFreq;
            excForce = (excitementTarget - excitementLevel) * k;
            excForce = excForce - (excitementVelocity * c);

            // Update excitement velocity and position
            excAccel = excForce;
            excitementVelocity = excitementVelocity + (excAccel * dt);
            excitementLevel = (excitementLevel + (excitementVelocity * dt)).clip(0, 0.999);

            // === FATIGUE DYNAMICS ===
            // Calculate fatigue target
            if(noiseLevel > 0) {
                // Noise reduces fatigue target slowly (not instant)
                fatigueTarget = (fatigueTarget - (dt * 0.15)).max(0);
            } {
                // Fatigue builds when excitement is high without noise
                if(excitementLevel > 0.5) {
                    fatigueTarget = (fatigueTarget + (dt * 0.08 * excitementLevel)).min(1.0);
                } {
                    // Slow natural recovery when excitement is low
                    fatigueTarget = (fatigueTarget - (dt * 0.05)).max(0);
                };
            };

            // Determine if fatigue is rising or falling
            fatIsRising = fatigueTarget > fatigueLevel;

            // Select spring parameters for fatigue
            if(fatIsRising) {
                fatSpringFreq = fatRisingFreq;
                fatSpringDamp = fatRisingDamp;
            } {
                fatSpringFreq = fatFallingFreq;
                fatSpringDamp = fatFallingDamp;
            };

            // Calculate spring force for fatigue
            k = (2pi * fatSpringFreq).squared;
            c = 2 * fatSpringDamp * 2pi * fatSpringFreq;
            fatForce = (fatigueTarget - fatigueLevel) * k;
            fatForce = fatForce - (fatigueVelocity * c);

            // Update fatigue velocity and position
            fatAccel = fatForce;
            fatigueVelocity = fatigueVelocity + (fatAccel * dt);
            fatigueLevel = (fatigueLevel + (fatigueVelocity * dt)).clip(0, 1);

            // Decay noise level
            noiseLevel = (noiseLevel - (dt * 2.5)).max(0);

            dt.wait;
        }
    };

    // Dog barking logic routine
    fork {
        loop {
            var shouldBark, numDogs, barkProbability;
            var effectiveFeedback;

            // Calculate effective feedback (reduced by fatigue)
            effectiveFeedback = baseFeedback * (1.0 - (fatigueLevel * 0.8));

            // Higher excitement = more feedback, but modulated by fatigue
            effectiveFeedback = effectiveFeedback * (1.0 + (excitementLevel * 2));

            // Calculate bark probability
            barkProbability = excitementLevel * (1.0 - (fatigueLevel * 0.5));

            // Determine if dogs should bark
            if(excitementLevel > excitementThreshold) {
                shouldBark = barkProbability.coin;

                if(shouldBark) {
                    if(dogBuffers.isNil) {
                        // Use synthesized barks if no samples loaded
                        if(activeDogs < maxDogs) {
                            numDogs = (excitementLevel.linlin(0.3, 1, 1, 4).round).asInteger;
                            numDogs = numDogs.min(maxDogs - activeDogs).min(1);

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

                                // Direct excitement boost from pack feedback
                                excitementLevel = (excitementLevel + (effectiveFeedback * rrand(0.5, 1.0))).min(0.999);

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
                                var rate = rrand(0.85, 1.15);
                                var amp = excitementLevel.linlin(0, 1, 0.4, 1.0);
                                var duration = buffer.duration / rate;

                                Synth(\dogBark, [
                                    \buf, buffer,
                                    \pan, pan,
                                    \rate, rate,
                                    \amp, amp
                                ]);

                                activeDogs = activeDogs + 1;

                                // Direct excitement boost from pack feedback
                                excitementLevel = (excitementLevel + (effectiveFeedback * rrand(0.5, 1.0))).min(0.999);

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
            var fatigueBar = barChar ! (fatigueLevel * 20).round;

            "\n=== Dog Neighbourhood Simulator ===".postln;
            ("Noise Level:" + noiseLevel.round(0.1) + noiseBar.join).postln;
            ("Excitement:" + excitementLevel.round(0.01) + excitementBar.join).postln;
            ("Fatigue:" + fatigueLevel.round(0.02) + fatigueBar.join).postln;
            ("Active Dogs:" + activeDogs + "/" + maxDogs).postln;
            "".postln;
            ("Excitement Spring: ↑freq" + excRisingFreq.round(0.1) +
             " ↑damp" + excRisingDamp.round(0.01) +
             " ↓freq" + excFallingFreq.round(0.1) +
             " ↓damp" + excFallingDamp.round(0.01)).postln;
            ("Fatigue Spring: ↑freq" + fatRisingFreq.round(0.1) +
             " ↑damp" + fatRisingDamp.round(0.01) +
             " ↓freq" + fatFallingFreq.round(0.1) +
             " ↓damp" + fatFallingDamp.round(0.01)).postln;

            if(excitementLevel > 0.5 and: { fatigueLevel > 0.5 }) {
                "  [Dogs getting tired - feedback weakening]".postln;
            };

            "".postln;
            "Keys: 0-9 = noise, q/a w/s e/d r/f = exc springs".postln;
            "      t/g y/h u/j i/k = fatigue springs, ESC = quit".postln;

            0.1.wait;
        }
    };

    // Keyboard input
    w = Window("Dog Simulator Control", Rect(100, 100, 500, 300)).front;
    w.view.keyDownAction = { |view, char, modifiers, unicode, keycode|
        case
        // Number keys 0-9 for noise level
        { char.isDecDigit } {
            var noiseBurst = char.digit;
            noiseLevel = (noiseLevel + noiseBurst).min(9);
            ("Noise burst:" + noiseBurst + "-> total:" + noiseLevel.round(0.1)).postln;

            // Immediate velocity boost for sudden noise
            if(noiseBurst > 5) {
                excitementVelocity = excitementVelocity + (noiseBurst * 0.02);
            };
        }

        // Excitement spring controls
        { char == $q } { excRisingFreq = (excRisingFreq + 0.2).min(10); ("Exc rise freq:" + excRisingFreq).postln; }
        { char == $a } { excRisingFreq = (excRisingFreq - 0.2).max(0.1); ("Exc rise freq:" + excRisingFreq).postln; }
        { char == $w } { excRisingDamp = (excRisingDamp + 0.05).min(2); ("Exc rise damp:" + excRisingDamp).postln; }
        { char == $s } { excRisingDamp = (excRisingDamp - 0.05).max(0.05); ("Exc rise damp:" + excRisingDamp).postln; }
        { char == $e } { excFallingFreq = (excFallingFreq + 0.1).min(5); ("Exc fall freq:" + excFallingFreq).postln; }
        { char == $d } { excFallingFreq = (excFallingFreq - 0.1).max(0.1); ("Exc fall freq:" + excFallingFreq).postln; }
        { char == $r } { excFallingDamp = (excFallingDamp + 0.05).min(2); ("Exc fall damp:" + excFallingDamp).postln; }
        { char == $f } { excFallingDamp = (excFallingDamp - 0.05).max(0.05); ("Exc fall damp:" + excFallingDamp).postln; }

        // Fatigue spring controls
        { char == $t } { fatRisingFreq = (fatRisingFreq + 0.1).min(5); ("Fat rise freq:" + fatRisingFreq).postln; }
        { char == $g } { fatRisingFreq = (fatRisingFreq - 0.1).max(0.1); ("Fat rise freq:" + fatRisingFreq).postln; }
        { char == $y } { fatRisingDamp = (fatRisingDamp + 0.05).min(2); ("Fat rise damp:" + fatRisingDamp).postln; }
        { char == $h } { fatRisingDamp = (fatRisingDamp - 0.05).max(0.05); ("Fat rise damp:" + fatRisingDamp).postln; }
        { char == $u } { fatFallingFreq = (fatFallingFreq + 0.1).min(5); ("Fat fall freq:" + fatFallingFreq).postln; }
        { char == $j } { fatFallingFreq = (fatFallingFreq - 0.1).max(0.1); ("Fat fall freq:" + fatFallingFreq).postln; }
        { char == $i } { fatFallingDamp = (fatFallingDamp + 0.05).min(2); ("Fat fall damp:" + fatFallingDamp).postln; }
        { char == $k } { fatFallingDamp = (fatFallingDamp - 0.05).max(0.05); ("Fat fall damp:" + fatFallingDamp).postln; }

        // ESC to quit
        { keycode == 27 } { w.close; };
    };

    w.onClose = {
        "Dog Simulator stopped".postln;
    };

    "".postln;
    "=== Dog Neighbourhood Simulator Started ===".postln;
    "".postln;
    "EXCITEMENT SPRING CONTROLS:".postln;
    "  q/a = rising frequency up/down".postln;
    "  w/s = rising damping up/down".postln;
    "  e/d = falling frequency up/down".postln;
    "  r/f = falling damping up/down".postln;
    "".postln;
    "FATIGUE SPRING CONTROLS:".postln;
    "  t/g = rising frequency up/down".postln;
    "  y/h = rising damping up/down".postln;
    "  u/j = falling frequency up/down".postln;
    "  i/k = falling damping up/down".postln;
    "".postln;
};
);