-- Live settings read by physics, camera and HUD. Rates are Betaflight rates per axis (RC Rate, Rate, RC Expo),
-- stored in hundredths as Betaflight does, with its classic defaults 1.00 / 0.70 / 0.00.
local values = {
  camAngle = 45,
  -- 1 LOW, 2 MED, 3 HIGH
  quality = 3,
  angleMode = false,
  batterySim = true,
  rollRcRate = 100,
  rollRate = 70,
  rollExpo = 0,
  pitchRcRate = 100,
  pitchRate = 70,
  pitchExpo = 0,
  yawRcRate = 100,
  yawRate = 70,
  yawExpo = 0,
  maxAngle = 55,
  -- Diagonal, in degrees
  fov = 95,
  fps = false,
  -- 2 ALL, 1 NO MOTOR (event cues only), 0 OFF
  sound = 1,
  haptic = true,
  -- Control axes: the input each one reads (getValue source names) and whether it is reversed
  rollSrc = "ail",
  pitchSrc = "ele",
  yawSrc = "rud",
  thrSrc = "thr",
  rollRev = false,
  pitchRev = false,
  yawRev = false,
  thrRev = false,
  -- The arm switch (or any source); "always": no switch
  armSrc = "always",
  armRev = false,
}

return values
