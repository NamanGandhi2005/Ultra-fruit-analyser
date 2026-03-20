# Ultra-Fruit-Analyser: Pi 5 Setup Progress

## Current State
- **Hardware:** Raspberry Pi 5.
- **Displays:** Two 16x2 LCDs.
  - **LCD 1 (Primary):** Connected to I2C-1. Address `0x27` (Verified).
  - **LCD 2 (Secondary):** Connected to I2C-0. Address `0x22` (Verified via `i2cdetect`).
- **Software:** `pi_automated_analyzer.py` is operational using the `myenv` virtual environment.

## Progress
1. [x] **Enable I2C-0:** Confirmed `dtparam=i2c_vc=on` is in `/boot/firmware/config.txt`.
2. [x] **Verify Detection:** `i2cdetect` confirmed `0x27` on Bus 1 and `0x22` on Bus 0.
3. [ ] **Update Script:** Change `lcd2_addr` to `0x22` in `pi_automated_analyzer.py`.
4. [ ] **Test Execution:** Verify both displays show data simultaneously.

## Findings
- LCD 2 was found at address `0x22` on Bus 0, not `0x3f` as previously assumed.
- The system correctly identifies fruits (e.g., Orange, Mango) and displays nutrient data.
- Rot detection logic is active.

## Command Reference
- **Edit Config:** `sudo nano /boot/firmware/config.txt`
- **Scan Bus 1:** `i2cdetect -y 1`
- **Scan Bus 0:** `i2cdetect -y 0`
- **Run Analyzer:** `python pi_automated_analyzer.py`
