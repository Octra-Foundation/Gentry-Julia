module GentryAlg

using StaticArrays
export gentry-jl

mutable struct StateMachine
        state_number::Int32
        previous_state::Int32
        state_count::Vector{UInt32}
        general_table::SVector{256,Int32}
        function StateMachine(block = 256)
            b(i)=(i & 1) * 2 + (i & 2) + (i >> 2 & 1) + (i >> 3 & 1) + (i >> 4 & 1) + (i >> 5 & 1) + (i >> 6 & 1) + (i >> 7 & 1) + 3
            state_count = [b(i) << 28 | 6 for i in 0:block-1]
            general_table = UInt32[32768 ÷ (i + i + 3) for i in 0:255]
            previous_state = 0
            new(block, previous_state, state_count, general_table)
        end
end

function next_block!(sm::StateMachine, state)::UInt32
    @assert state >= 0 && state < sm.state_number
    sm.previous_state = state
    return sm.state_count[state+1] >> 16
end

function update!(sm::StateMachine, rm_vector, limit=255)::Nothing
    block = sm.state_count[sm.previous_state+1] & 255
    next_block = sm.state_count[sm.previous_state+1] >> 14

    if block < limit
        sm.state_count[sm.previous_state+1] += 1
        delta = (((rm_vector << 18) - next_block) * sm.general_table[block+1]) & 0xffffff00
        sm.state_count[sm.previous_state+1] = unsafe_trunc(UInt32, sm.state_count[sm.previous_state+1] + delta)
    end
    nothing
end

mutable struct Determinant
    previsions_state::Int32
    directed_graph::StateMachine
    state::MVector{256,Int32}
    Determinant(previsions_state=0, directed_graph = StateMachine(0x10000)) = new(previsions_state, directed_graph, fill(Int32(0x66), 256))
end

next_block!(det::Determinant)::UInt32 = next_block!(det.directed_graph, det.previsions_state << 8 | det.state[det.previsions_state+1])

function update!(det::Determinant, rm_vector)::Nothing
    update!(det.directed_graph, rm_vector, 90) # limit = 90
    state_numeration = Ref(det.state, det.previsions_state+1) # Ref to det.state[det.previsions_state+1]
    state_numeration[] += state_numeration[] + rm_vector
    state_numeration[] &= 255
    if (det.previsions_state += det.previsions_state + rm_vector) >= 256
        det.previsions_state = 0
    end
    nothing
end
     
@enum Mode ENCODE_DATA DECODE_DATA

mutable struct Encoder
    determinant::Determinant
    mode::Mode
    block::IOStream
    vector_x::UInt32
    vector_y::UInt32
    lambda::UInt32
    function Encoder(io_mode::Mode, file_stream::IOStream)
        lambda = 0
        if io_mode == DECODE_DATA
            for i in 1:4
                if eof(file_stream)
                    byte = UInt8(0)
                else
                    byte = read(file_stream, UInt8)
                end
                lambda = (lambda << 8) + (byte & 0xff)
            end
        end
        vector_x = 0
        vector_y = 0xffffffff
        new(Determinant(), io_mode, file_stream, vector_x, vector_y, lambda)
    end
end 

        
function alignment!(enc::Encoder)::Nothing
    if enc.codec_mode == DECODE_DATA
        return nothing
    end
    while iscondition(enc.vector_x, enc.vector_y) # (((enc.vector_x ⊻ enc.vector_y) & 0xff000000) == 0)
        #write(AP, unsafe_trunc(UInt8, enc.vector_y >> 24))
        enc.vector_x, enc.vector_y = shifts(enc.vector_x, enc.vector_y) #enc.vector_x <<= 8; enc.vector_y = (enc.vector_y << 8) + 255
    end
    write(enc.soup, unsafe_trunc(UInt8, enc.vector_y >> 24))
    nothing
end # function alignment!

@inline iscondition(vector_x,vector_y) = (((vector_x ⊻ vector_y) & 0xff000000) == 0)

@inline shifts(vector_x, vector_y) = (vector_x <<= 8, (vector_y << 8) + 255)
