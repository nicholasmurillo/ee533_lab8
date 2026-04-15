ADDI r1, r0, 1

wait_ready:
LW r2, 0x3F0(r0)
SW r1, 0x310(r0)
BNE r1, r2, wait_ready

LW r3, 0x3E4(r0)
SW r3, 0x300(r0)
ADDI r3, r3, 10
SW r3, 0x3E4(r0)
SW r1, 0x3F1(r0)
SW r3, 0x301(r1)


