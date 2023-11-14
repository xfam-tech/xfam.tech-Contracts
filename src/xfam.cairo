use starknet::ContractAddress;

#[starknet::interface]
trait IXFam<TContractState>{
    fn get_protocol_fee_destination(self: @TContractState) -> ContractAddress;
    fn get_protocol_fee_percent(self: @TContractState) -> u256;
    fn get_subject_fee_percent(self: @TContractState) -> u256;
    fn get_holder_fee_percent(self: @TContractState) -> u256; 
    fn get_referral_fee_percent(self: @TContractState) -> u256;
    fn get_shares_balance(self: @TContractState, shares_subject: ContractAddress, user: ContractAddress) -> u256;
    fn get_shares_supply(self: @TContractState, shares_subject: ContractAddress) -> u256;
    fn set_protocol_fee_destination(ref self: TContractState, fee_destination: ContractAddress);
    fn set_protocol_fee_percent(ref self: TContractState, fee_percent: u256);
    fn set_subject_fee_percent(ref self: TContractState, fee_percent: u256);
    fn set_holder_fee_percent(ref self: TContractState, fee_percent: u256);
    fn set_referral_fee_percent(ref self: TContractState, fee_percent: u256);
    fn set_owner(ref self: TContractState, owner: ContractAddress);
    fn get_price(self: @TContractState, supply: u256, amount: u256) -> u256;
    fn get_buy_price(self:@TContractState, shares_subject: ContractAddress, amount: u256) -> u256;
    fn get_sell_price(self: @TContractState, shares_subject: ContractAddress, amount: u256) -> u256;
    fn get_buy_price_after_fee(self: @TContractState, shares_subject: ContractAddress, amount: u256) -> u256;
    fn get_sell_price_after_fee(self: @TContractState, shares_subject: ContractAddress, amount: u256) -> u256;
    fn buy_shares(ref self: TContractState, shares_subject: ContractAddress, amount: u256, value: u256);
    fn sell_shares(ref self: TContractState, shares_subject: ContractAddress, amount: u256);
    fn set_public_key(ref self: TContractState, public_key: felt252);
    fn claim_holder_ref_reward(ref self: TContractState, 
        id: u256,
        to: ContractAddress, 
        amount: u256, 
        exp_time: u256, 
        signature_r: felt252, 
        signature_s: felt252);
}

#[starknet::contract]
mod XFam {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use ecdsa::{check_ecdsa_signature};
    use keccak::keccak_u256s_be_inputs;
    use xfam::token::ieth::IETHDispatcher;
    use xfam::token::ieth::IETHDispatcherTrait;

    #[storage]
    struct Storage {
        _owner: ContractAddress,
        _protocol_fee_destination: ContractAddress,
        _holder_and_referral_fee_destination: ContractAddress,
        _protocol_fee_percent: u256,
        _subject_fee_percent: u256,
        _holder_fee_percent: u256,
        _referral_fee_percent: u256,
        _shares_balance: LegacyMap<(ContractAddress, ContractAddress), u256>,
        _shares_supply: LegacyMap<ContractAddress, u256>,
        _ETH: ContractAddress,
        _ONE_ETH : u256,

        _signature_r_history: LegacyMap<felt252, bool>,
        _signature_s_history: LegacyMap<felt252, bool>,
        _hash_history: LegacyMap<felt252, bool>,
        _id_history: LegacyMap<u256, bool>,
        _public_key: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Trade: Trade,
        Transfer: Transfer
    }

    #[derive(Drop, starknet::Event)]
    struct Trade {
        trader: ContractAddress,
        subject: ContractAddress,
        is_buy: bool,
        share_amount: u256,
        eth_amount: u256,
        protocol_eth_amount: u256,
        subject_eth_amount: u256,
        holder_eth_amount: u256,
        referral_eth_amount: u256,
        supply: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        id: u256,
        to: ContractAddress,
        amount: u256,
        exp_time: u256
    }

    
    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, ETH: ContractAddress, public_key: felt252) {
        self._owner.write(owner);
        self._ETH.write(ETH);
        self._ONE_ETH.write(1000000000000000000);
        self._protocol_fee_percent.write(25000000000000000);
        self._subject_fee_percent.write(50000000000000000);
        self._holder_fee_percent.write(50000000000000000);
        self._referral_fee_percent.write(200000000000000000);

        self._public_key.write(public_key);
    }

    #[external(v0)]
    impl ImplIXFamExternal of super::IXFam<ContractState> {
        fn get_protocol_fee_destination(self: @ContractState) -> ContractAddress {
            return self._protocol_fee_destination.read();
        }

        fn get_protocol_fee_percent(self: @ContractState) -> u256 {
            return self._protocol_fee_percent.read();
        }

        fn get_subject_fee_percent(self: @ContractState) -> u256 {
            return self._subject_fee_percent.read();
        }

        fn get_holder_fee_percent(self: @ContractState) -> u256 {
            return self._holder_fee_percent.read();
        }

        fn get_referral_fee_percent(self: @ContractState) -> u256 {
            return self._referral_fee_percent.read();
        }

        fn get_shares_balance(self: @ContractState, shares_subject: ContractAddress, user: ContractAddress) -> u256 {
            return self._shares_balance.read((shares_subject, user));
        }

        fn get_shares_supply(self: @ContractState, shares_subject: ContractAddress) -> u256 {
            return self._shares_supply.read(shares_subject);
        }
        
        fn set_protocol_fee_destination(ref self: ContractState, fee_destination: ContractAddress) {
            let caller: ContractAddress = get_caller_address();
            assert(self._owner.read() == caller, 'Caller is not owner');
            self._protocol_fee_destination.write(fee_destination);
        }

        fn set_protocol_fee_percent(ref self: ContractState, fee_percent: u256) {
            let caller: ContractAddress = get_caller_address();
            assert(self._owner.read() == caller, 'Caller is not owner');
            self._protocol_fee_percent.write(fee_percent);
        }

        fn set_subject_fee_percent(ref self: ContractState, fee_percent: u256) {
            let caller: ContractAddress = get_caller_address();
            assert(self._owner.read() == caller, 'Caller is not owner');
            self._subject_fee_percent.write(fee_percent);
        }

        fn set_holder_fee_percent(ref self: ContractState, fee_percent: u256) {
            let caller: ContractAddress = get_caller_address();
            assert(self._owner.read() == caller, 'Caller is not owner');
            self._holder_fee_percent.write(fee_percent);
        }

        fn set_referral_fee_percent(ref self: ContractState, fee_percent: u256) {
            let caller: ContractAddress = get_caller_address();
            assert(self._owner.read() == caller, 'Caller is not owner');
            self._referral_fee_percent.write(fee_percent);
        }

        fn set_owner(ref self: ContractState, owner: ContractAddress) {
            let caller: ContractAddress = get_caller_address();
            assert(self._owner.read() == caller, 'Caller is not owner');
            self._owner.write(owner);
        }

        fn get_price(self: @ContractState, supply: u256, amount: u256) -> u256 {
            return self._get_price(supply, amount);
        }

        fn get_buy_price(self:@ContractState, shares_subject: ContractAddress, amount: u256) -> u256 {
            return self._get_buy_price(shares_subject, amount);
        }

        fn get_sell_price(self: @ContractState, shares_subject: ContractAddress, amount: u256) -> u256 {
            return self._get_sell_price(shares_subject, amount);
        }

        fn get_buy_price_after_fee(self: @ContractState, shares_subject: ContractAddress, amount: u256) -> u256 {
            let price :u256 = self._get_buy_price(shares_subject, amount);
            let protocol_fee: u256 = price * self._protocol_fee_percent.read() / self._ONE_ETH.read();
            let subject_fee: u256 = price * self._subject_fee_percent.read() / self._ONE_ETH.read();
            let holder_fee: u256 = price * self._holder_fee_percent.read() / self._ONE_ETH.read();
            return price + protocol_fee + subject_fee + holder_fee;
        }

        fn get_sell_price_after_fee(self: @ContractState, shares_subject: ContractAddress, amount: u256) -> u256 {
            let price :u256 = self._get_sell_price(shares_subject, amount);
            let protocol_fee: u256 = price * self._protocol_fee_percent.read() / self._ONE_ETH.read();
            let subject_fee: u256 = price * self._subject_fee_percent.read() / self._ONE_ETH.read();
            let holder_fee: u256 = price * self._holder_fee_percent.read() / self._ONE_ETH.read();
            return price - protocol_fee - subject_fee - holder_fee;
        }

        fn buy_shares(ref self: ContractState, shares_subject: ContractAddress, amount: u256, value: u256) {
            let caller = get_caller_address();
            let success1 :bool = IETHDispatcher{ contract_address: self._ETH.read() }.transferFrom(caller, get_contract_address(), value);
            let supply :u256 = self._shares_supply.read(shares_subject);
            // assert(supply > 0 || shares_subject == caller, 'Only the shares subject can buy');
            assert(amount > 0, 'amount invalid');
            let price :u256 = self._get_price(supply, amount);
            let protocol_fee: u256 = price * self._protocol_fee_percent.read() / self._ONE_ETH.read();
            let subject_fee: u256 = price * self._subject_fee_percent.read() / self._ONE_ETH.read();
            let holder_fee: u256 = price * self._holder_fee_percent.read() / self._ONE_ETH.read();
            let referral_fee :u256 = protocol_fee * self._referral_fee_percent.read() / self._ONE_ETH.read();
            assert(value >= price + protocol_fee + subject_fee + holder_fee, 'Insuficient payment');
            self._shares_balance.write((shares_subject, caller), self._shares_balance.read((shares_subject, caller)) + amount);
            self._shares_supply.write(shares_subject, supply + amount);
            self.emit(Trade{
                trader: caller,
                subject: shares_subject,
                is_buy: true,
                share_amount: amount,
                eth_amount: price,
                protocol_eth_amount: protocol_fee,
                subject_eth_amount: subject_fee,
                holder_eth_amount: holder_fee,
                referral_eth_amount: referral_fee,
                supply: supply + amount,
            });

            let protocol_value :u256 = protocol_fee - (protocol_fee*self._referral_fee_percent.read()/self._ONE_ETH.read());
            let subject_value :u256 = subject_fee;

            let success2 :bool = IETHDispatcher{ contract_address: self._ETH.read() }.transfer(self._protocol_fee_destination.read(), protocol_value);
            let success3 :bool = IETHDispatcher{ contract_address: self._ETH.read() }.transfer(shares_subject, subject_value);

            assert(success1 && success2 && success3, 'Unable to send found');
        }

        fn sell_shares(ref self: ContractState, shares_subject: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            let supply :u256 = self._shares_supply.read(shares_subject);
            assert(amount > 0, 'amount invalid');
            let price :u256 = self._get_price(supply-amount, amount);
            let protocol_fee :u256 = price * self._protocol_fee_percent.read() / self._ONE_ETH.read();
            let subject_fee :u256 = price * self._subject_fee_percent.read() / self._ONE_ETH.read();
            let referral_fee :u256 = protocol_fee * self._referral_fee_percent.read() / self._ONE_ETH.read();
            assert(self._shares_balance.read((shares_subject, caller)) >= amount, 'Insuficient payment');
            self._shares_balance.write((shares_subject, caller), self._shares_balance.read((shares_subject, caller)) - amount);
            self._shares_supply.write(shares_subject, supply - amount);
            
            self.emit(Trade{
                trader: caller,
                subject: shares_subject,
                is_buy: false,
                share_amount: amount,
                eth_amount: price,
                protocol_eth_amount: protocol_fee,
                subject_eth_amount: subject_fee,
                holder_eth_amount: 0,
                referral_eth_amount: referral_fee,
                supply: supply - amount,
            });

            let caller_value :u256 = price - protocol_fee - subject_fee;
            let protocol_value :u256 = protocol_fee - (protocol_fee*self._referral_fee_percent.read()/self._ONE_ETH.read());
            let subject_value :u256 = subject_fee;
            
            let success1: bool = IETHDispatcher{ contract_address: self._ETH.read() }.transfer(caller, caller_value);
            let success2: bool = IETHDispatcher{ contract_address: self._ETH.read() }.transfer(self._protocol_fee_destination.read(), protocol_value);
            let success3: bool = IETHDispatcher{ contract_address: self._ETH.read() }.transfer(shares_subject, subject_value);

            assert(success1 && success2 && success3, 'Unable to send founds');
        }

        fn claim_holder_ref_reward(ref self: ContractState, 
            id: u256,
            to: ContractAddress, 
            amount: u256, 
            exp_time: u256, 
            signature_r: felt252, 
            signature_s: felt252) {
                assert(!self._id_history.read(id), 'id is unique');
                assert(exp_time > get_block_timestamp().into(), 'exp time invalid');
                assert(!to.is_zero(), 'to address invalid');
                let hash: felt252 = self._create_hash(id, to, amount, exp_time).try_into().unwrap();
                assert(!self._hash_history.read(hash), 'hash is used');
                assert(!self._signature_r_history.read(signature_r), 'signature_r is used');
                assert(!self._signature_s_history.read(signature_s), 'signature_s is used');
                assert(self._is_valid_signature(hash, signature_r, signature_s), 'invalid signature');
                IETHDispatcher{ contract_address: self._ETH.read() }.transfer(to, amount);
                self._hash_history.write(hash, true);
                self._signature_r_history.write(signature_r, true);
                self._signature_s_history.write(signature_s, true);
                self._id_history.write(id, true);
                self.emit(Transfer{
                    id: id,
                    to: to,
                    amount: amount,
                    exp_time: exp_time
                })
        }

        fn set_public_key(ref self: ContractState, public_key: felt252) {
            let caller :ContractAddress = get_caller_address();
            assert(caller == self._owner.read(), 'Caller is not owner');
            self._public_key.write(public_key);
        }
    }

    #[generate_trait]
    impl ImplIXFamInternal of IXFamInternal {
        fn _get_price(self: @ContractState, supply: u256, amount: u256) -> u256 {
            if amount == 0 {
                return 0;
            }
            let sum1 :u256 = supply * (supply + 1)*(2*(supply + 1))/6;
            let sum2 :u256 = (supply + amount)*(supply + 1 + amount)*(2*(supply + amount) + 1)/6;
            let summation : u256 = sum2 - sum1;
            return summation * self._ONE_ETH.read()/20000;
        }

        fn _get_buy_price(self:@ContractState, shares_subject: ContractAddress, amount: u256) -> u256 {
            return self._get_price(self._shares_supply.read(shares_subject), amount);
        }

        fn _get_sell_price(self: @ContractState, shares_subject: ContractAddress, amount: u256) -> u256 {
            return self._get_price(self._shares_supply.read(shares_subject) - amount, amount);
        }

        fn _is_valid_signature(self: @ContractState, hash: felt252, signature_r: felt252, signature_s: felt252) -> bool {
            check_ecdsa_signature(
                hash, self._public_key.read(), signature_r, signature_s
            )
        }

        fn _create_hash(self: @ContractState, id: u256, to: ContractAddress, amount: u256, exp_time: u256) -> u256 {
            let mut input: Array<u256> = ArrayTrait::new();
            let into :felt252 = to.into();
            input.append(id);
            input.append(into.into());
            input.append(amount);
            input.append(exp_time);
            
            keccak_u256s_be_inputs(input.span())/32
        }
    }
}