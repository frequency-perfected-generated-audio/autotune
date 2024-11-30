use clap::Parser;
use hound::WavReader;
use num_traits::FromPrimitive;

#[derive(Parser)]
struct Config {
    #[arg(long)]
    window_size: usize,
    #[arg(long)]
    taumax: usize,
    #[arg(long)]
    file: String,
}

fn yin(sig: &[u16], window_size: usize, taumax: usize) -> u16 {
    let mut diff = vec![0; taumax];
    let mut cumdiff = vec![0.0; taumax];

    diff[0] = 1; // this value doesn't actually matter
    cumdiff[0] = f32::from_i16(1).unwrap();

    // autocorrelate
    for tau in 1..taumax {
        for i in 0..(window_size - tau) {
            let samp = sig[i] as usize;
            let offseted = sig[i + tau] as usize;
            diff[tau] += (samp - offseted) * (samp - offseted);
        }
        cumdiff[tau] = f32::from_usize(tau * diff[tau]).unwrap()
            / (diff.iter().skip(1).take(tau).sum::<usize>() as f32);
    }

    let mut diff_min = f32::MAX;
    let mut tau_min = 0;
    for tau in 1..taumax {
        if cumdiff[tau] < diff_min {
            tau_min = tau;
            diff_min = cumdiff[tau];
        }
        if diff_min < 0.1 {
            while tau_min + 1 < taumax && cumdiff[tau_min + 1] < cumdiff[tau_min] {
                tau_min += 1;
            }
            break;
        }
    }

    tau_min as u16
}

fn main() {
    let Config {
        window_size,
        taumax,
        file,
    } = Config::parse();
    let mut reader = WavReader::open(file).unwrap();
    let sig = reader
        .samples::<i16>()
        .map(|i| (i.unwrap() as u16) ^ 0x8000u16)
        .collect::<Vec<u16>>();

    for chunk in sig.chunks_exact(window_size) {
        println!("{}", yin(chunk, window_size, taumax))
    }
}
