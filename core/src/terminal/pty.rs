use crate::CoreError;
use parking_lot::Mutex;
use portable_pty::{native_pty_system, CommandBuilder, PtyPair, PtySize};
use std::io::{Read, Write};
use std::path::Path;
use std::sync::Arc;

pub struct PtyHandle {
    pair: PtyPair,
    writer: Arc<Mutex<Box<dyn Write + Send>>>,
    reader: Arc<Mutex<Box<dyn Read + Send>>>,
    child: Option<Box<dyn portable_pty::Child + Send + Sync>>,
}

impl PtyHandle {
    pub fn spawn<P: AsRef<Path>>(working_dir: P, cols: u16, rows: u16) -> Result<Self, CoreError> {
        let pty_system = native_pty_system();

        let pair = pty_system
            .openpty(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| CoreError::Pty(e.to_string()))?;

        let mut cmd = CommandBuilder::new_default_prog();
        cmd.cwd(working_dir.as_ref());

        let child = pair
            .slave
            .spawn_command(cmd)
            .map_err(|e| CoreError::Pty(e.to_string()))?;

        let writer = pair
            .master
            .take_writer()
            .map_err(|e| CoreError::Pty(e.to_string()))?;

        let reader = pair
            .master
            .try_clone_reader()
            .map_err(|e| CoreError::Pty(e.to_string()))?;

        Ok(Self {
            pair,
            writer: Arc::new(Mutex::new(writer)),
            reader: Arc::new(Mutex::new(reader)),
            child: Some(child),
        })
    }

    pub fn write(&self, data: &[u8]) -> Result<usize, CoreError> {
        let mut writer = self.writer.lock();
        writer.write(data).map_err(CoreError::Io)
    }

    pub fn read(&self, buf: &mut [u8]) -> Result<usize, CoreError> {
        let mut reader = self.reader.lock();
        reader.read(buf).map_err(CoreError::Io)
    }

    pub fn resize(&self, cols: u16, rows: u16) -> Result<(), CoreError> {
        self.pair
            .master
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| CoreError::Pty(e.to_string()))
    }

    pub fn is_alive(&mut self) -> bool {
        if let Some(ref mut child) = self.child {
            child.try_wait().ok().flatten().is_none()
        } else {
            false
        }
    }

    pub fn terminate(&mut self) -> Result<(), CoreError> {
        if let Some(mut child) = self.child.take() {
            child.kill().map_err(|e| CoreError::Pty(e.to_string()))?;
        }
        Ok(())
    }

    pub fn get_reader(&self) -> Arc<Mutex<Box<dyn Read + Send>>> {
        self.reader.clone()
    }

    pub fn get_writer(&self) -> Arc<Mutex<Box<dyn Write + Send>>> {
        self.writer.clone()
    }
}
