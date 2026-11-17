DefinitionBlock ("", "SSDT", 2, "GXTEST", "GXFPRSRC", 1)
{
    Scope (\_SB)
    {
        Device (GPI0)
        {
            Name (_HID, "GXFT0003")
        }
        Device (PC00)
        {
            Name (_HID, "GXFT0001")
            Device (SPI1)
            {
                Name (_HID, "GXFT0002")
                Device (FPNT)
                {
#ifdef WRONG_HID
                    Name (_HID, "TEST5120")
#else
                    Name (_HID, "GXFP5120")
#endif
                    Name (_UID, One)
                    Name (IGPI, 279)
                    Name (OGPI, 15)
                    Method (_CRS, 0, Serialized)
                    {
                        Name (BBUF, ResourceTemplate ()
                        {
                            SpiSerialBusV2 (0, PolarityLow, FourWireMode, 8,
                                ControllerInitiated, 10000000, ClockPolarityLow,
                                ClockPhaseFirst, "\\_SB.PC00.SPI1",
                                0, ResourceConsumer, , Exclusive, )
                            GpioInt (Edge, ActiveHigh, ExclusiveAndWake, PullDefault, 0,
                                "\\_SB.GPI0", 0, ResourceConsumer, , ) { 0 }
                            GpioIo (Exclusive, PullUp, 0, 0, IoRestrictionOutputOnly,
                                "\\_SB.GPI0", 0, ResourceConsumer, , ) { 8 }
                        })
                        CreateWordField (BBUF, 0x3B, GPIN)
                        CreateWordField (BBUF, 0x5E, SPIN)
                        GPIN = IGPI
                        SPIN = OGPI
                        Return (BBUF)
                    }
                }
            }
        }
    }
}
