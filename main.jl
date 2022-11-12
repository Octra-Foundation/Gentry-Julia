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
