import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * LogiStep Security Shield
 * ------------------------
 * Coklu is parcacigi (Multi-Threaded) yapisi ile yetkili ag portlarini
 * denetleyen ve siber guvenlik uyumlulugunu kontrol eden servis omurgasi.
 * CCNA / siber guvenlik ilkelerine dayali temel uyumluluk taramasi yapar.
 *
 * Derleme/Calistirma:
 *     javac SecurityScanner.java
 *     java SecurityScanner [hedef_ip]
 */
public class SecurityScanner {

    // Eszamanli tarama icin Thread havuzu
    private static final int THREAD_POOL_SIZE = 10;
    private static final int TIMEOUT_MS = 200;

    public static void main(String[] args) {
        System.out.println("LogiStep Security Shield: Netzwerkpruefung gestartet...");

        // Hedef IP arguman olarak verilebilir, verilmezse localhost kullanilir
        String targetIp = (args.length > 0) ? args[0] : "127.0.0.1";

        // Sadece yetkili ve guvenli portlar (HTTPS, SAP RFC, SAP Gateway)
        int[] securePorts = {443, 3300, 3301, 8443};

        scanNetwork(targetIp, securePorts);
    }

    public static void scanNetwork(String ip, int[] ports) {
        ExecutorService executor = Executors.newFixedThreadPool(THREAD_POOL_SIZE);
        AtomicInteger openCount = new AtomicInteger(0);
        AtomicInteger closedCount = new AtomicInteger(0);

        for (int port : ports) {
            executor.submit(() -> {
                try (Socket socket = new Socket()) {
                    socket.connect(new InetSocketAddress(ip, port), TIMEOUT_MS);
                    System.out.println("[SICHER] Port " + port + " ist offen und autorisiert.");
                    openCount.incrementAndGet();
                } catch (Exception e) {
                    System.out.println("[GEBLOCKT] Port " + port + " ist geschlossen oder nicht erreichbar.");
                    closedCount.incrementAndGet();
                }
            });
        }

        executor.shutdown();
        try {
            if (!executor.awaitTermination(5, TimeUnit.SECONDS)) {
                executor.shutdownNow();
            }
        } catch (InterruptedException e) {
            System.err.println("Scan-Vorgang unterbrochen!");
            Thread.currentThread().interrupt();
        }

        System.out.println("------------------------------------------");
        System.out.printf(
            "Sicherheitspruefung abgeschlossen: %d offen, %d geschlossen.%n",
            openCount.get(), closedCount.get()
        );
    }
}
