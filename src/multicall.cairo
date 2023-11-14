#[starknet::contract]
mod multicall {
    use starknet::{ContractAddress, call_contract_syscall, SyscallResultTrait};
    use array::ArrayTrait;

    #[storage]
    struct Storage {
        
    }

    #[derive(Drop, Serde)]
    struct Call {
        to: ContractAddress,
        selector: felt252,
        calldata: Array<felt252>
    }

    #[external(v0)]
    #[generate_trait]
    impl ImplMulticallInternal of IMultiCallInternal {
        fn execute_multiple_calls(self: @ContractState, mut calls: Array<Call>) -> Array<Span<felt252>> {
            let mut res = ArrayTrait::new();
            loop {
                match calls.pop_front() {
                    Option::Some(one_call) => {
                        let _res = self.execute_single_call(one_call);
                        res.append(_res);
                    },
                    Option::None(_) => {
                        break ();
                    },
                };
            };
            return res;
        }

        fn execute_single_call(self: @ContractState, one_call: Call) -> Span<felt252> {
            let Call{to, selector, calldata } = one_call;
            call_contract_syscall(to, selector, calldata.span()).unwrap_syscall()
        }
    }
}