import Foundation

public enum Slurm {
    private static func int(_ key: String) -> Int? {
        guard let value = ProcessInfo.processInfo.environment[key],
              let intValue = Int(value) else { return nil }
        return intValue
    }

    private static func string(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    private static func boolFlag(_ key: String) -> Bool {
        ProcessInfo.processInfo.environment[key] != nil
    }

    /// Total number of tasks in a job array
    public static var arrayTaskCount: Int? { int("SLURM_ARRAY_TASK_COUNT") }

    /// Job array ID (index) number
    public static var arrayTaskId: Int? { int("SLURM_ARRAY_TASK_ID") }

    /// Job array's maximum ID (index) number
    public static var arrayTaskMax: Int? { int("SLURM_ARRAY_TASK_MAX") }

    /// Job array's minimum ID (index) number
    public static var arrayTaskMin: Int? { int("SLURM_ARRAY_TASK_MIN") }

    /// Job array's index step size
    public static var arrayTaskStep: Int? { int("SLURM_ARRAY_TASK_STEP") }

    /// Job array's master job ID number
    public static var arrayJobId: Int? { int("SLURM_ARRAY_JOB_ID") }

    /// The SLURM job ID
    public static var jobId: Int? { int("SLURM_JOB_ID") }

    /// The SLURM job name
    public static var jobName: String? { string("SLURM_JOB_NAME") }

    /// The partition the job is running on
    public static var jobPartition: String? { string("SLURM_JOB_PARTITION") }

    /// Submit host
    public static var submitHost: String? { string("SLURM_SUBMIT_HOST") }

    /// Directory from which the job was submitted
    public static var submitDir: String? { string("SLURM_SUBMIT_DIR") }

    /// Path to stdout file
    public static var stdoutPath: String? { string("SLURM_JOB_STDOUT") }

    /// Path to stderr file
    public static var stderrPath: String? { string("SLURM_JOB_STDERR") }

    /// Number of nodes allocated
    public static var jobNumNodes: Int? { int("SLURM_JOB_NUM_NODES") }

    /// List of allocated nodes (compressed form)
    public static var jobNodeList: String? { string("SLURM_JOB_NODELIST") }

    /// Number of nodes requested
    public static var ntasksPerNode: Int? { int("SLURM_NTASKS_PER_NODE") }

    /// Total number of tasks
    public static var ntasks: Int? { int("SLURM_NTASKS") }

    /// Tasks per node
    public static var tasksPerNode: String? { string("SLURM_TASKS_PER_NODE") }

    /// Current node ID (relative to allocation)
    public static var nodeId: Int? { int("SLURM_NODEID") }

    /// Name of the current node
    public static var nodeName: String? { string("SLURMD_NODENAME") }

    // CPU Resources
    /// CPUs per task
    public static var cpusPerTask: Int? { int("SLURM_CPUS_PER_TASK") }

    /// Total CPUs on node allocated to job
    public static var jobCpusPerNode: String? { string("SLURM_JOB_CPUS_PER_NODE") }

    /// Number of CPUs available to the job
    public static var cpusOnNode: Int? { int("SLURM_CPUS_ON_NODE") }

    /// Local task ID (for MPI rank within node)
    public static var localId: Int? { int("SLURM_LOCALID") }

    /// Global task ID (MPI rank)
    public static var procId: Int? { int("SLURM_PROCID") }


    /// Memory per node (MB)
    public static var memPerNode: Int? { int("SLURM_MEM_PER_NODE") }

    /// Memory per CPU (MB)
    public static var memPerCpu: Int? { int("SLURM_MEM_PER_CPU") }

    /// GPUs per node
    public static var gpusOnNode: Int? { int("SLURM_GPUS_ON_NODE") }

    /// GPUs per task
    public static var gpusPerTask: Int? { int("SLURM_GPUS_PER_TASK") }

    /// CUDA visible devices (if set by SLURM)
    public static var cudaVisibleDevices: String? { string("CUDA_VISIBLE_DEVICES") }

    /// The UNIX timestamp for a job's start time
    public static var startTime: Int? { int("SLURM_JOB_START_TIME") }

    /// The UNIX timestamp for a job's projected end time
    public static var endTime: Int? { int("SLURM_JOB_END_TIME") }

    /// True if job was requeued
    public static var requeueCount: Int? { int("SLURM_RESTART_COUNT") }

    /// True if running inside a SLURM allocation
    public static var isRunningUnderSlurm: Bool {
        boolFlag("SLURM_JOB_ID")
    }
}