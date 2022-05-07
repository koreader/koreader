# Unit Tests

Unit tests are automatically performed using [busted](http://olivinelabs.com/busted/). It depends on `luarocks`.

To grab busted, install the same version [as used in the automated tests](https://github.com/koreader/koreader/blob/master/.ci/install.sh). At the time of writing that is 2.0.0-1:
```bash
mkdir $HOME/.luarocks
cp /etc/luarocks/config.lua $HOME/.luarocks/config.lua
echo "wrap_bin_scripts = false" >> $HOME/.luarocks/config.lua
luarocks --local install busted 2.0.0-1
```
Then you can set up the environment variables with `./kodev activate`.

If all went well, you'll now be able to run `./kodev test front` (for the frontend) or `./kodev test base` (for koreader-base).

You can run individual tests using `./kodev test front testname_spec.lua`.
