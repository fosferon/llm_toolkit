network_tests = System.get_env("LLM_TOOLKIT_NETWORK_TESTS") in ["1", "true"]

ExUnit.start(exclude: if(network_tests, do: [], else: [:network]))
