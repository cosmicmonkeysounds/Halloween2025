/*
Neighbourhood Dog Simulator
for "Dog Gong It" installation
*/

(
// Boot server if needed
s.waitForBoot {
    var dogBuffers, dogPaths;
    var noiseLevel = 0, excitementLevel = 0;
    var excitementVelocity = 0;
    var lastExcitementLevel = 0;

    // Spring parameters (2nd order system)
    var risingFreq = 2.0, risingDamp = 0.3;  // Faster rise, less damping
    var fallingFreq = 0.5, fallingDamp = 0.7; // Slower fall, more damping

    // Dog behavior parameters
    var excitementThreshold = 0.3;  // Min excitement to start barking
    var packFeedback = 0.15;        // How much each bark adds to excitement
    var maxDogs = 8;                 // Max simultaneous dogs
    var activeDogs = 0;

    // Timing
    var updateRate = 60;             // Hz for spring update
    var barkCheckRate = 10;          // Hz for checking if dogs should bark

    // Load dog samples
    dogPaths = (PathName("dogs".resolveRelative).files).select({ |f|
        f.extension == "wav" or: { f.extension == "WAV" }
    });

    if(dogPaths.size == 0) {
        "No WAV files found in 'dogs' folder!".warn;
        "Please ensure there's a 'dogs' folder with WAV files in the same directory".postln;
    } {
        ("Found" + dogPaths.size + "dog samples").postln;
        dogBuffers = dogPaths.collect({ |path|
            Buffer.read(s, path.fullPath);
        });
    };

    s.sync;

    // SynthDef for playing dog barks
    SynthDef(\dogBark, { |out=0, buf=0, pan=0, amp=0.5, rate=1|
        var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rate, doneAction: 2);
        sig = sig * amp * EnvGen.kr(Env.linen(0.01, 0.1, 0.1), doneAction: 2);
        Out.ar(out, Pan2.ar(sig, pan));
    }).add;

    s.sync;

    // Spring dynamics update routine
    fork {
        loop {
            var targetExcitement, springFreq, springDamp;
            var dt = 1.0 / updateRate;
            var force, acceleration;
            var isRising, k, c;

            // Determine target based on noise level
            targetExcitement = noiseLevel.linlin(0, 9, 0, 1.0);

            // Add pack feedback effect
            targetExcitement = (targetExcitement + (excitementLevel * packFeedback)).min(1.0);

            // Determine if we're rising or falling
            isRising = targetExcitement > excitementLevel;

            // Select spring parameters based on direction
            if(isRising) {
                springFreq = risingFreq;
                springDamp = risingDamp;
            } {
                springFreq = fallingFreq;
                springDamp = fallingDamp;
            };

            // Calculate spring force (F = -kx - cv)
            // k = (2π * freq)^2, c = 2 * damping * 2π * freq
            k = (2pi * springFreq).squared;
            c = 2 * springDamp * 2pi * springFreq;

            force = (targetExcitement - excitementLevel) * k;
            force = force - (excitementVelocity * c);

            // Update velocity and position
            acceleration = force;  // assuming mass = 1
            excitementVelocity = excitementVelocity + (acceleration * dt);
            excitementLevel = (excitementLevel + (excitementVelocity * dt)).clip(0, 1);

            // Decay noise level slightly over time
            if(noiseLevel > 0) {
                noiseLevel = (noiseLevel - (dt * 0.5)).max(0);
            };

            dt.wait;
        }
    };

    // Dog barking logic routine
    fork {
        loop {
            var shouldBark, numDogs, barkProbability;

            // Calculate bark probability based on excitement and noise
            barkProbability = (excitementLevel * 0.7) + (noiseLevel.linlin(0, 9, 0, 0.3));

            // Determine how many dogs should bark
            if(excitementLevel > excitementThreshold or: { noiseLevel > 2 }) {
                shouldBark = barkProbability.coin;

                if(shouldBark and: { dogBuffers.notNil } and: { activeDogs < maxDogs }) {
                    // Number of dogs increases with excitement
                    numDogs = (excitementLevel.linlin(0.3, 1, 1, 3).round).asInteger;
                    numDogs = numDogs.min(maxDogs - activeDogs);

                    numDogs.do {
                        var buffer = dogBuffers.choose;
                        var pan = 1.0.rand2;  // Random pan -1 to 1
                        var rate = rrand(0.9, 1.1);  // Slight pitch variation
                        var amp = excitementLevel.linlin(0, 1, 0.3, 0.8);

                        Synth(\dogBark, [
                            \buf, buffer,
                            \pan, pan,
                            \rate, rate,
                            \amp, amp
                        ]);

                        activeDogs = activeDogs + 1;

                        // Add to pack excitement (positive feedback)
                        excitementLevel = (excitementLevel + packFeedback.rand).min(1.0);

                        // Schedule dog count decrease
                        fork {
                            (buffer.duration / rate).wait;
                            activeDogs = activeDogs - 1;
                        };

                        // Small random delay between dogs
                        rrand(0.05, 0.2).wait;
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

            "\n=== Dog Neighbourhood Simulator ===".postln;
            ("Noise Level [0-9]:" + noiseLevel.round(0.1) + noiseBar.join).postln;
            ("Excitement:" + excitementLevel.round(0.01) + excitementBar.join).postln;
            ("Active Dogs:" + activeDogs + "/" + maxDogs).postln;
            ("Spring: freq(↑" + risingFreq + "↓" + fallingFreq + ") " +
             "damp(↑" + risingDamp + "↓" + fallingDamp + ")").postln;
            "".postln;
            "Keys: 0-9 = noise level, q/a = rise freq, w/s = rise damp".postln;
            "      e/d = fall freq, r/f = fall damp, ESC = quit".postln;

            0.1.wait;
        }
    };

    // Keyboard input
    w = Window("Dog Simulator Control", Rect(100, 100, 400, 200)).front;
    w.view.keyDownAction = { |view, char, modifiers, unicode, keycode|
        case
        // Number keys 0-9 for noise level
        { char.isDecDigit } {
            noiseLevel = char.digit;
            ("Noise level set to:" + noiseLevel).postln;

            // Add immediate excitement boost for sudden noise
            if(noiseLevel > 5) {
                excitementVelocity = excitementVelocity + (noiseLevel * 0.1);
            };
        }

        // Spring parameter controls
        { char == $q } { risingFreq = (risingFreq + 0.2).min(10); ("Rising freq:" + risingFreq).postln; }
        { char == $a } { risingFreq = (risingFreq - 0.2).max(0.1); ("Rising freq:" + risingFreq).postln; }
        { char == $w } { risingDamp = (risingDamp + 0.05).min(2); ("Rising damp:" + risingDamp).postln; }
        { char == $s } { risingDamp = (risingDamp - 0.05).max(0.05); ("Rising damp:" + risingDamp).postln; }
        { char == $e } { fallingFreq = (fallingFreq + 0.1).min(5); ("Falling freq:" + fallingFreq).postln; }
        { char == $d } { fallingFreq = (fallingFreq - 0.1).max(0.1); ("Falling freq:" + fallingFreq).postln; }
        { char == $r } { fallingDamp = (fallingDamp + 0.05).min(2); ("Falling damp:" + fallingDamp).postln; }
        { char == $f } { fallingDamp = (fallingDamp - 0.05).max(0.05); ("Falling damp:" + fallingDamp).postln; }

        // ESC to quit
        { keycode == 27 } { w.close; };
    };

    w.onClose = {
        "Dog Simulator stopped".postln;
    };

    "".postln;
    "=== Dog Neighbourhood Simulator Started ===".postln;
    "Use number keys 0-9 to set noise level".postln;
    "Additional controls for spring tuning:".postln;
    "  q/a = rising frequency up/down".postln;
    "  w/s = rising damping up/down".postln;
    "  e/d = falling frequency up/down".postln;
    "  r/f = falling damping up/down".postln;
    "".postln;
};
);