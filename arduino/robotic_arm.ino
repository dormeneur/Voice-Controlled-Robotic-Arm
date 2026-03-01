#include <Servo.h>

// ── Servo objects ──────────────────────────────────────────────────────
Servo baseServo;
Servo shoulderServo;
Servo elbowServo;
Servo gripperServo;

// ── Servo pins ─────────────────────────────────────────────────────────
const int BASE_PIN = 3;
const int SHOULDER_PIN = 5;
const int ELBOW_PIN = 6;
const int GRIPPER_PIN = 9;

// ── Current angles ─────────────────────────────────────────────────────
int baseAngle = 90;
int shoulderAngle = 90;
int elbowAngle = 90;
int gripperAngle = 90;

// ── Movement config ────────────────────────────────────────────────────
const int STEP = 10;
const int MIN_ANGLE = 0;
const int MAX_ANGLE = 180;

// ── Helpers ────────────────────────────────────────────────────────────
int clampAngle(int angle)
{
    if (angle < MIN_ANGLE)
        return MIN_ANGLE;
    if (angle > MAX_ANGLE)
        return MAX_ANGLE;
    return angle;
}

void resetPosition()
{
    baseAngle = 90;
    shoulderAngle = 90;
    elbowAngle = 90;
    gripperAngle = 90;

    baseServo.write(baseAngle);
    shoulderServo.write(shoulderAngle);
    elbowServo.write(elbowAngle);
    gripperServo.write(gripperAngle);
}

// ── Setup ──────────────────────────────────────────────────────────────
void setup()
{
    // HC-05 default baud rate
    Serial.begin(9600);

    baseServo.attach(BASE_PIN);
    shoulderServo.attach(SHOULDER_PIN);
    elbowServo.attach(ELBOW_PIN);
    gripperServo.attach(GRIPPER_PIN);

    resetPosition();
}

// ── Loop ───────────────────────────────────────────────────────────────
void loop()
{
    if (Serial.available() > 0)
    {
        char cmd = Serial.read();

        switch (cmd)
        {
        case 'L': // Move base left
            baseAngle = clampAngle(baseAngle - STEP);
            baseServo.write(baseAngle);
            break;

        case 'R': // Move base right
            baseAngle = clampAngle(baseAngle + STEP);
            baseServo.write(baseAngle);
            break;

        case 'U': // Move shoulder up
            shoulderAngle = clampAngle(shoulderAngle - STEP);
            shoulderServo.write(shoulderAngle);
            break;

        case 'D': // Move shoulder down
            shoulderAngle = clampAngle(shoulderAngle + STEP);
            shoulderServo.write(shoulderAngle);
            break;

        case 'P': // Close gripper (pick)
            gripperAngle = clampAngle(gripperAngle - STEP);
            gripperServo.write(gripperAngle);
            break;

        case 'O': // Open gripper (release)
            gripperAngle = clampAngle(gripperAngle + STEP);
            gripperServo.write(gripperAngle);
            break;

        case 'X': // Reset all servos to neutral
            resetPosition();
            break;
        }
    }
}
