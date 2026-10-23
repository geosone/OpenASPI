// Hash-pinned static DOS API research; no vendor code is executed.
// Import as raw x86:LE:16:Real Mode at 0000:0000. One report-path argument.
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.MemoryBlock;
import java.math.BigInteger;
import java.io.PrintWriter;

// The two supported modules use different entry conventions: the SYTOS
// callback table versus DOS device strategy/interrupt header words. Hash and
// raw-import checks select that interpretation before any table offset is used.
// The report records observed callbacks; it is not an authoritative declaration
// of inferred argument types, register preservation or native OpenTape semantics.
public class InspectDosTapeApi extends GhidraScript {
    public void run() throws Exception {
        String hash = currentProgram.getExecutableSHA256();
        boolean sytos = "5ca618abec3e714971a4c6677c1041586bbee355c3a3860a934e3827f491afbf".equalsIgnoreCase(hash);
        boolean aspi = "161de4d65082e4a5c8dc8f7b2ba75463c4e36d9f61739b3c715ac05bdd05fde9".equalsIgnoreCase(hash);
        Address base = currentProgram.getMinAddress();
        if (getScriptArgs().length != 1 || (!sytos && !aspi) ||
            !base.toString().equals("0000:0000") ||
            !currentProgram.getLanguageID().toString().equals("x86:LE:16:Real Mode")) {
            throw new IllegalArgumentException("Expected pinned raw DOS module at 0000:0000 and report path");
        }
        for (MemoryBlock block : currentProgram.getMemory().getBlocks()) {
            currentProgram.getProgramContext().setValue(currentProgram.getRegister("DS"),
                block.getStart(), block.getEnd(), BigInteger.ZERO);
        }
        if (sytos) {
            for (int p = 0x100; p < 0x154; p += 2) {
                seed(base, currentProgram.getMemory().getShort(base.add(p)) & 0xffff);
            }
        } else {
            seed(base, currentProgram.getMemory().getShort(base.add(6)) & 0xffff);
            seed(base, currentProgram.getMemory().getShort(base.add(8)) & 0xffff);
        }
        analyzeAll(currentProgram);
        DecompInterface decompiler = new DecompInterface();
        if (!decompiler.openProgram(currentProgram)) throw new IllegalStateException("Decompiler failed");
        try (PrintWriter out = new PrintWriter(getScriptArgs()[0])) {
            out.println("SHA256 " + hash);
            out.println("Static raw-module analysis; registers, far pointers and inferred types need review.");
            if (sytos) {
                for (int p = 0x100; p < 0x154; p += 2) {
                    out.printf("CALLBACK %02X -> %04X%n", (p - 0x100) / 2,
                        currentProgram.getMemory().getShort(base.add(p)) & 0xffff);
                }
            }
            int count = 0;
            FunctionIterator functions = currentProgram.getFunctionManager().getFunctions(true);
            while (functions.hasNext() && !monitor.isCancelled()) {
                Function f = functions.next();
                count++;
                out.println("\n// FUNCTION " + f.getEntryPoint());
                DecompileResults r = decompiler.decompileFunction(f, 10, monitor);
                out.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : r.getErrorMessage());
                out.println("// DISASSEMBLY " + f.getEntryPoint());
                InstructionIterator instructions = currentProgram.getListing().getInstructions(f.getBody(), true);
                while (instructions.hasNext()) {
                    Instruction i = instructions.next();
                    out.println(i.getAddress() + " " + i.toString());
                }
            }
            out.println("FUNCTION_COUNT " + count);
        } finally {
            decompiler.dispose();
        }
    }

    private void seed(Address base, int offset) throws Exception {
        Address address = base.add(offset);
        if (!currentProgram.getMemory().contains(address)) throw new IllegalArgumentException("Bad entry offset");
        disassemble(address);
        if (getFunctionAt(address) == null && getFunctionContaining(address) == null) {
            createFunction(address, "api_" + Integer.toHexString(offset));
        }
    }
}
