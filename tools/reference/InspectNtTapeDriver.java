// Static research of hash-pinned x86 NT tape drivers. Never executes them.
// Argument: output report path under ignored build/ (contains vendor output).
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.Reference;
import java.io.PrintWriter;
import java.util.Set;

// PE imports retain image-base/loader semantics; do not apply DOS raw-image
// DS/offset assumptions here. Reports combine strings/xrefs, caller links,
// decompiled functions and disassembly so a device-specific branch can be traced
// back to its actual code. A string or inferred type alone is not a proven quirk.
// Use the documented ignored report location; the argument itself is not a path
// restriction enforced by this script.
public class InspectNtTapeDriver extends GhidraScript {
    private static final Set<String> HASHES = Set.of(
        "4b7c638087f6c8c953ab76951c55af31f50d05ea98c9cd3d587e4391b3702052",
        "8e65c16cad4810316641156e23619af201941878d5f260d88f7fa253e63d97cc",
        "aa8165e8801590c05b129d7de9f912d30c75d3f93367f3cbeed31c51f3ca08b6",
        "3eca6c45bd1a6ac2d3da06677483494193b71c18f6e27de3f20db2ed145f2c24",
        "39fc1be3c537b6e4206183b9b75a64f4d43fb45fb52dcfc2c45540afcbfa23da",
        "af9381c9746f5f18f322c1abe89900187976f2059c2207085a6d9739ff6e4681"
    );

    public void run() throws Exception {
        String hash = currentProgram.getExecutableSHA256();
        if (getScriptArgs().length != 1 || hash == null ||
            !HASHES.contains(hash.toLowerCase())) {
            throw new IllegalArgumentException("Expected pinned NT tape PE and one report path");
        }
        if (!currentProgram.getLanguageID().toString().equals("x86:LE:32:default") ||
            !currentProgram.getExecutableFormat().contains("Portable Executable")) {
            throw new IllegalArgumentException("Expected x86 PE import, not raw DOS image");
        }
        DecompInterface decompiler = new DecompInterface();
        if (!decompiler.openProgram(currentProgram)) {
            throw new IllegalStateException("Could not open decompiler");
        }
        try (PrintWriter out = new PrintWriter(getScriptArgs()[0])) {
            out.println("PROGRAM " + currentProgram.getName());
            out.println("SHA256 " + hash);
            out.println("IMAGE_BASE " + currentProgram.getImageBase());
            out.println("Static analysis; inferred NT types require disassembly review.");
            DataIterator data = currentProgram.getListing().getDefinedData(true);
            while (data.hasNext() && !monitor.isCancelled()) {
                Data d = data.next();
                if (!d.hasStringValue()) continue;
                out.println("\nSTRING " + d.getAddress() + " " + d.getDefaultValueRepresentation());
                for (Reference ref : getReferencesTo(d.getAddress())) {
                    Function caller = getFunctionContaining(ref.getFromAddress());
                    out.println("  XREF " + ref.getFromAddress() + " FUNCTION " +
                        (caller == null ? "unknown" : caller.getEntryPoint()));
                }
            }
            int count = 0;
            FunctionIterator functions = currentProgram.getFunctionManager().getFunctions(true);
            while (functions.hasNext() && !monitor.isCancelled()) {
                Function f = functions.next();
                if (f.isExternal()) continue;
                count++;
                out.println("\n// FUNCTION " + f.getEntryPoint() + " " + f.getName());
                for (Reference ref : getReferencesTo(f.getEntryPoint())) {
                    out.println("// CALLER " + ref.getFromAddress());
                }
                DecompileResults r = decompiler.decompileFunction(f, 10, monitor);
                out.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : r.getErrorMessage());
                out.println("// DISASSEMBLY " + f.getEntryPoint());
                InstructionIterator instructions = currentProgram.getListing().getInstructions(f.getBody(), true);
                while (instructions.hasNext()) {
                    Instruction i = instructions.next();
                    out.println(i.getAddress() + " " + i.toString());
                }
            }
            out.println("\nFUNCTION_COUNT " + count);
        } finally {
            decompiler.dispose();
        }
    }
}
