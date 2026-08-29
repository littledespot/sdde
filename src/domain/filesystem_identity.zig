pub const FileIdentity = struct {
    filesystem_id: u128,
    file_id: u128,
    generation_id: u128 = 0,

    pub fn eql(left: FileIdentity, right: FileIdentity) bool {
        return left.filesystem_id == right.filesystem_id and
            left.file_id == right.file_id and
            left.generation_id == right.generation_id;
    }
};
