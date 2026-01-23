use crate::CoreError;
use std::path::Path;

pub struct PtyHandle {
    _placeholder: (),
}

impl PtyHandle {
    pub fn spawn<P: AsRef<Path>>(_working_dir: P) -> Result<Self, CoreError> {
        Ok(Self { _placeholder: () })
    }

    pub fn write(&mut self, _data: &[u8]) -> Result<usize, CoreError> {
        Ok(0)
    }

    pub fn resize(&mut self, _cols: u16, _rows: u16) -> Result<(), CoreError> {
        Ok(())
    }

    pub fn terminate(&mut self) -> Result<(), CoreError> {
        Ok(())
    }
}
