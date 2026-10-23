// Local static compatibility research; never executes the vendor driver.
// Import documented ASPIDISK.SYS/ASPICD.SYS as raw x86:LE:16:Real Mode at 0.
// Script argument: output report path (keep generated vendor output untracked).
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.mem.MemoryBlock;
import java.io.PrintWriter;
import java.math.BigInteger;

public class InspectAspiDriver extends GhidraScript {
    public void run() throws Exception {
        if (getScriptArgs().length != 1) {
            throw new IllegalArgumentException("Expected output report path");
        }
        String expected = currentProgram.getExecutableSHA256();
        boolean cd = "72b7166f457751e0461f6b3a99ce0dd0b19fd8396def9b196eb00467428c78fb".equalsIgnoreCase(expected);
        if (!cd && !"3066b40ed15ae6ddc8211d9434eb3c2ff078f0170e7f527ead0daca08ae044ee".equalsIgnoreCase(expected)) {
            throw new IllegalArgumentException("Not a documented ASPIDISK 4.01b / ASPICD 4.01 binary");
        }
        Address base = currentProgram.getMinAddress();
        if (base.getOffset() != 0 || !base.toString().equals("0000:0000")) {
            throw new IllegalArgumentException("Expected raw real-mode image at 0000:0000");
        }
        for (MemoryBlock block : currentProgram.getMemory().getBlocks()) {
            currentProgram.getProgramContext().setValue(currentProgram.getRegister("DS"),
                block.getStart(), block.getEnd(), BigInteger.ZERO);
        }
        int[] extra = cd ? new int[] {0x25e, 0x269} : new int[] {0x12, 0x1d, 0x263, 0x291, 0x2d5, 0x2e6, 0x322,
            0x407, 0x460, 0x473, 0x556, 0x154a, 0x1604, 0x164c};
        for (int offset : extra) {
            seed(base, offset);
        }
        // Table offset, count, first command/minor. Read bounds from ASPICD.
        int[][] tables = cd ? new int[][] {
            {0x1c, currentProgram.getMemory().getByte(base.add(0x3e)) & 0xff, 0},
            {0x40, currentProgram.getMemory().getByte(base.add(0x54)) & 0xff, 0x80},
            {0x3fc, currentProgram.getMemory().getShort(base.add(0x41e)) & 0xffff, 0},
            {0x97f, currentProgram.getMemory().getShort(base.add(0x98d)) & 0xffff, 0}
        } : new int[][] {{0x13b7, 27, 0}};
        for (int[] table : tables) {
            if (table[1] < 1 || table[1] > 64) {
                throw new IllegalArgumentException("Invalid dispatch table size");
            }
            for (int index = 0; index < table[1]; index++) {
                int offset = currentProgram.getMemory().getShort(base.add(table[0] + index * 2)) & 0xffff;
                if (offset != 0) {
                    seed(base, offset);
                }
            }
        }
        analyzeAll(currentProgram);
        DecompInterface decompiler = new DecompInterface();
        if (!decompiler.openProgram(currentProgram)) {
            throw new IllegalStateException("Could not open decompiler");
        }
        try (PrintWriter out = new PrintWriter(getScriptArgs()[0])) {
            out.println((cd ? "ASPICD.SYS 4.01" : "ASPIDISK.SYS 4.01b") + " SHA-256 " + expected);
            out.println("Static analysis only; reconstructed types/register arguments need review.");
            for (int[] table : tables) {
                out.printf("\nDispatch table at file/image %04Xh:%n", table[0]);
                for (int index = 0; index < table[1]; index++) {
                    int offset = currentProgram.getMemory().getShort(base.add(table[0] + index * 2)) & 0xffff;
                    out.printf("%02X -> %04X%n", index + table[2], offset);
                }
            }
            FunctionIterator functions = currentProgram.getFunctionManager().getFunctions(true);
            while (functions.hasNext() && !monitor.isCancelled()) {
                Function f = functions.next();
                out.println("\n// FUNCTION " + f.getEntryPoint());
                DecompileResults r = decompiler.decompileFunction(f, 10, monitor);
                out.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : r.getErrorMessage());
            }
        } finally {
            decompiler.dispose();
        }
    }

    private void seed(Address base, int offset) throws Exception {
        Address entry = base.add(offset);
        disassemble(entry);
        if (getFunctionAt(entry) == null && getFunctionContaining(entry) == null) {
            createFunction(entry, "inspect_" + Integer.toHexString(offset));
        }
    }
}
