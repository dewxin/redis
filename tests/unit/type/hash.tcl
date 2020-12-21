start_server {tags {"hash"}} {
    test {HSET/HLEN - Small hash creation} {
        array set smallhash {}
        for {set i 0} {$i < 8} {incr i} {
            set key __avoid_collisions__[randstring 0 8 alpha]
            set val __avoid_collisions__[randstring 0 8 alpha]
            if {[info exists smallhash($key)]} {
                incr i -1
                continue
            }
            r hset smallhash $key $val
            set smallhash($key) $val
        }
        list [r hlen smallhash]
    } {8}

    test {Is the small hash encoded with a ziplist?} {
        assert_encoding ziplist smallhash
    }

    proc create_hash {key entries} {
        r del $key
        foreach entry $entries { r hset $key $entry 1 }
    }

    foreach {type contents} "ziplist {1 2 3} hashtable {a b c[randstring 70 90 alpha]}" {

        test "HRANDMEMBER - $type" {
            create_hash myhash $contents;
            assert_encoding $type myhash
            unset -nocomplain myhash
            array set myhash {}
            for {set i 0} {$i < 100} {incr i} {
                lassign [r hrandmember myhash] key val
                set myhash($key) $val
            }
            assert_equal [lsort $contents] [lsort [array names myhash]]
        }
    }


    test "HRANDMEMBER with <count> against non existing key" {
        r hrandmember nonexisting_key 100
    } {}

    foreach {type contents} "
        hashtable {
            1 5 10 50 125 50000 33959417 4775547 65434162
            12098459 427716 483706 2726473884 72615637475
            MARY PATRICIA LINDA BARBARA ELIZABETH JENNIFER MARIA
            SUSAN MARGARET DOROTHY LISA NANCY KAREN BETTY HELEN
            SANDRA DONNA CAROL RUTH SHARON MICHELLE LAURA SARAH
            KIMBERLY DEBORAH JESSICA SHIRLEY CYNTHIA ANGELA MELISSA
            BRENDA AMY ANNA REBECCA VIRGINIA c[randstring 70 90 alpha]
        }
        ziplist {
            0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19
            20 21 22 23 24 25 26 27 28 2d9
            30 31 32 33 34 35 36 37 38 39
            40 41 42 43 44 45 46 47 48 49
        }
    " {
        test "HRANDMEMBER with <count> - $type" {
            create_hash myhash $contents
            unset -nocomplain myhash
            foreach ele [r hkeys myhash] {
                dict append myhash $ele 1
            }
            assert_equal [lsort $contents] [lsort [dict keys $myhash]]

            # Make sure that a count of 0 is handled correctly.
            assert_equal [r hrandmember myhash 0] {}

            # We'll stress different parts of the code, see the implementation
            # of HRANDMEMBER for more information, but basically there are
            # four different code paths.
            #
            # PATH 1: Use negative count.
            #
            # 1) Check that it returns repeated elements.
            set res [r hrandmember myhash 100]
            # assert_equal [llength $res] 200
            # If not asked, decide not to implement this feature.

            # 2) Check that all the elements actually belong to the
            # original set.
            foreach {key val} $res {
                assert {[dict exists $myhash $key]}
            }

            # 3) Check that eventually all the elements are returned.
            unset -nocomplain auxset
            set iterations 1000
            while {$iterations != 0} {
                incr iterations -1
                set res [r hrandmember myhash -10]
                foreach {key val} $res {
                    dict append auxset $key $val
                }
                if {[lsort [dict keys $myhash]] eq
                    [lsort [dict keys $auxset]]} {
                    break;
                }
            }
            assert {$iterations != 0}

            # PATH 2: positive count (unique behavior) with requested size
            # equal or greater than set size.
            foreach size {50 100} {
                set res [r hrandmember myhash $size]
                assert_equal [dict size $res] 50
                assert_equal [lsort [dict keys $res]] [lsort [dict keys $myhash]]
            }

            # PATH 3: Ask almost as elements as there are in the set.
            # In this case the implementation will duplicate the original
            # set and will remove random elements up to the requested size.
            #
            # PATH 4: Ask a number of elements definitely smaller than
            # the set size.
            #
            # We can test both the code paths just changing the size but
            # using the same code.

            foreach size {45 5} {
                set res [r hrandmember myhash $size]
                assert_equal [dict size $res] $size

                # 1) Check that all the elements actually belong to the
                # original set.
                foreach ele [dict keys $res] {
                    assert {[dict exists $myhash $ele]}
                }

                # 2) Check that eventually all the elements are returned.
                unset -nocomplain auxset
                set iterations 1000
                while {$iterations != 0} {
                    incr iterations -1
                    set res [r hrandmember myhash -10]
                    foreach {key value} $res {
                        dict append auxset $key $value
                    }
                    if {[lsort [dict keys $myhash]] eq
                        [lsort [dict keys $auxset]]} {
                        break;
                    }
                }
                assert {$iterations != 0}
            }
        }
    }


    test {HSET/HLEN - Big hash creation} {
        array set bighash {}
        for {set i 0} {$i < 1024} {incr i} {
            set key __avoid_collisions__[randstring 0 8 alpha]
            set val __avoid_collisions__[randstring 0 8 alpha]
            if {[info exists bighash($key)]} {
                incr i -1
                continue
            }
            r hset bighash $key $val
            set bighash($key) $val
        }
        list [r hlen bighash]
    } {1024}

    test {Is the big hash encoded with an hash table?} {
        assert_encoding hashtable bighash
    }

    test {HGET against the small hash} {
        set err {}
        foreach k [array names smallhash *] {
            if {$smallhash($k) ne [r hget smallhash $k]} {
                set err "$smallhash($k) != [r hget smallhash $k]"
                break
            }
        }
        set _ $err
    } {}

    test {HGET against the big hash} {
        set err {}
        foreach k [array names bighash *] {
            if {$bighash($k) ne [r hget bighash $k]} {
                set err "$bighash($k) != [r hget bighash $k]"
                break
            }
        }
        set _ $err
    } {}

    test {HGET against non existing key} {
        set rv {}
        lappend rv [r hget smallhash __123123123__]
        lappend rv [r hget bighash __123123123__]
        set _ $rv
    } {{} {}}

    test {HSET in update and insert mode} {
        set rv {}
        set k [lindex [array names smallhash *] 0]
        lappend rv [r hset smallhash $k newval1]
        set smallhash($k) newval1
        lappend rv [r hget smallhash $k]
        lappend rv [r hset smallhash __foobar123__ newval]
        set k [lindex [array names bighash *] 0]
        lappend rv [r hset bighash $k newval2]
        set bighash($k) newval2
        lappend rv [r hget bighash $k]
        lappend rv [r hset bighash __foobar123__ newval]
        lappend rv [r hdel smallhash __foobar123__]
        lappend rv [r hdel bighash __foobar123__]
        set _ $rv
    } {0 newval1 1 0 newval2 1 1 1}

    test {HSETNX target key missing - small hash} {
        r hsetnx smallhash __123123123__ foo
        r hget smallhash __123123123__
    } {foo}

    test {HSETNX target key exists - small hash} {
        r hsetnx smallhash __123123123__ bar
        set result [r hget smallhash __123123123__]
        r hdel smallhash __123123123__
        set _ $result
    } {foo}

    test {HSETNX target key missing - big hash} {
        r hsetnx bighash __123123123__ foo
        r hget bighash __123123123__
    } {foo}

    test {HSETNX target key exists - big hash} {
        r hsetnx bighash __123123123__ bar
        set result [r hget bighash __123123123__]
        r hdel bighash __123123123__
        set _ $result
    } {foo}

    test {HMSET wrong number of args} {
        catch {r hmset smallhash key1 val1 key2} err
        format $err
    } {*wrong number*}

    test {HMSET - small hash} {
        set args {}
        foreach {k v} [array get smallhash] {
            set newval [randstring 0 8 alpha]
            set smallhash($k) $newval
            lappend args $k $newval
        }
        r hmset smallhash {*}$args
    } {OK}

    test {HMSET - big hash} {
        set args {}
        foreach {k v} [array get bighash] {
            set newval [randstring 0 8 alpha]
            set bighash($k) $newval
            lappend args $k $newval
        }
        r hmset bighash {*}$args
    } {OK}

    test {HMGET against non existing key and fields} {
        set rv {}
        lappend rv [r hmget doesntexist __123123123__ __456456456__]
        lappend rv [r hmget smallhash __123123123__ __456456456__]
        lappend rv [r hmget bighash __123123123__ __456456456__]
        set _ $rv
    } {{{} {}} {{} {}} {{} {}}}

    test {HMGET against wrong type} {
        r set wrongtype somevalue
        assert_error "*wrong*" {r hmget wrongtype field1 field2}
    }

    test {HMGET - small hash} {
        set keys {}
        set vals {}
        foreach {k v} [array get smallhash] {
            lappend keys $k
            lappend vals $v
        }
        set err {}
        set result [r hmget smallhash {*}$keys]
        if {$vals ne $result} {
            set err "$vals != $result"
            break
        }
        set _ $err
    } {}

    test {HMGET - big hash} {
        set keys {}
        set vals {}
        foreach {k v} [array get bighash] {
            lappend keys $k
            lappend vals $v
        }
        set err {}
        set result [r hmget bighash {*}$keys]
        if {$vals ne $result} {
            set err "$vals != $result"
            break
        }
        set _ $err
    } {}

    test {HKEYS - small hash} {
        lsort [r hkeys smallhash]
    } [lsort [array names smallhash *]]

    test {HKEYS - big hash} {
        lsort [r hkeys bighash]
    } [lsort [array names bighash *]]

    test {HVALS - small hash} {
        set vals {}
        foreach {k v} [array get smallhash] {
            lappend vals $v
        }
        set _ [lsort $vals]
    } [lsort [r hvals smallhash]]

    test {HVALS - big hash} {
        set vals {}
        foreach {k v} [array get bighash] {
            lappend vals $v
        }
        set _ [lsort $vals]
    } [lsort [r hvals bighash]]

    test {HGETALL - small hash} {
        lsort [r hgetall smallhash]
    } [lsort [array get smallhash]]

    test {HGETALL - big hash} {
        lsort [r hgetall bighash]
    } [lsort [array get bighash]]

    test {HDEL and return value} {
        set rv {}
        lappend rv [r hdel smallhash nokey]
        lappend rv [r hdel bighash nokey]
        set k [lindex [array names smallhash *] 0]
        lappend rv [r hdel smallhash $k]
        lappend rv [r hdel smallhash $k]
        lappend rv [r hget smallhash $k]
        unset smallhash($k)
        set k [lindex [array names bighash *] 0]
        lappend rv [r hdel bighash $k]
        lappend rv [r hdel bighash $k]
        lappend rv [r hget bighash $k]
        unset bighash($k)
        set _ $rv
    } {0 0 1 0 {} 1 0 {}}

    test {HDEL - more than a single value} {
        set rv {}
        r del myhash
        r hmset myhash a 1 b 2 c 3
        assert_equal 0 [r hdel myhash x y]
        assert_equal 2 [r hdel myhash a c f]
        r hgetall myhash
    } {b 2}

    test {HDEL - hash becomes empty before deleting all specified fields} {
        r del myhash
        r hmset myhash a 1 b 2 c 3
        assert_equal 3 [r hdel myhash a b c d e]
        assert_equal 0 [r exists myhash]
    }

    test {HEXISTS} {
        set rv {}
        set k [lindex [array names smallhash *] 0]
        lappend rv [r hexists smallhash $k]
        lappend rv [r hexists smallhash nokey]
        set k [lindex [array names bighash *] 0]
        lappend rv [r hexists bighash $k]
        lappend rv [r hexists bighash nokey]
    } {1 0 1 0}

    test {Is a ziplist encoded Hash promoted on big payload?} {
        r hset smallhash foo [string repeat a 1024]
        r debug object smallhash
    } {*hashtable*}

    test {HINCRBY against non existing database key} {
        r del htest
        list [r hincrby htest foo 2]
    } {2}

    test {HINCRBY against non existing hash key} {
        set rv {}
        r hdel smallhash tmp
        r hdel bighash tmp
        lappend rv [r hincrby smallhash tmp 2]
        lappend rv [r hget smallhash tmp]
        lappend rv [r hincrby bighash tmp 2]
        lappend rv [r hget bighash tmp]
    } {2 2 2 2}

    test {HINCRBY against hash key created by hincrby itself} {
        set rv {}
        lappend rv [r hincrby smallhash tmp 3]
        lappend rv [r hget smallhash tmp]
        lappend rv [r hincrby bighash tmp 3]
        lappend rv [r hget bighash tmp]
    } {5 5 5 5}

    test {HINCRBY against hash key originally set with HSET} {
        r hset smallhash tmp 100
        r hset bighash tmp 100
        list [r hincrby smallhash tmp 2] [r hincrby bighash tmp 2]
    } {102 102}

    test {HINCRBY over 32bit value} {
        r hset smallhash tmp 17179869184
        r hset bighash tmp 17179869184
        list [r hincrby smallhash tmp 1] [r hincrby bighash tmp 1]
    } {17179869185 17179869185}

    test {HINCRBY over 32bit value with over 32bit increment} {
        r hset smallhash tmp 17179869184
        r hset bighash tmp 17179869184
        list [r hincrby smallhash tmp 17179869184] [r hincrby bighash tmp 17179869184]
    } {34359738368 34359738368}

    test {HINCRBY fails against hash value with spaces (left)} {
        r hset smallhash str " 11"
        r hset bighash str " 11"
        catch {r hincrby smallhash str 1} smallerr
        catch {r hincrby bighash str 1} bigerr
        set rv {}
        lappend rv [string match "ERR*not an integer*" $smallerr]
        lappend rv [string match "ERR*not an integer*" $bigerr]
    } {1 1}

    test {HINCRBY fails against hash value with spaces (right)} {
        r hset smallhash str "11 "
        r hset bighash str "11 "
        catch {r hincrby smallhash str 1} smallerr
        catch {r hincrby bighash str 1} bigerr
        set rv {}
        lappend rv [string match "ERR*not an integer*" $smallerr]
        lappend rv [string match "ERR*not an integer*" $bigerr]
    } {1 1}

    test {HINCRBY can detect overflows} {
        set e {}
        r hset hash n -9223372036854775484
        assert {[r hincrby hash n -1] == -9223372036854775485}
        catch {r hincrby hash n -10000} e
        set e
    } {*overflow*}

    test {HINCRBYFLOAT against non existing database key} {
        r del htest
        list [r hincrbyfloat htest foo 2.5]
    } {2.5}

    test {HINCRBYFLOAT against non existing hash key} {
        set rv {}
        r hdel smallhash tmp
        r hdel bighash tmp
        lappend rv [roundFloat [r hincrbyfloat smallhash tmp 2.5]]
        lappend rv [roundFloat [r hget smallhash tmp]]
        lappend rv [roundFloat [r hincrbyfloat bighash tmp 2.5]]
        lappend rv [roundFloat [r hget bighash tmp]]
    } {2.5 2.5 2.5 2.5}

    test {HINCRBYFLOAT against hash key created by hincrby itself} {
        set rv {}
        lappend rv [roundFloat [r hincrbyfloat smallhash tmp 3.5]]
        lappend rv [roundFloat [r hget smallhash tmp]]
        lappend rv [roundFloat [r hincrbyfloat bighash tmp 3.5]]
        lappend rv [roundFloat [r hget bighash tmp]]
    } {6 6 6 6}

    test {HINCRBYFLOAT against hash key originally set with HSET} {
        r hset smallhash tmp 100
        r hset bighash tmp 100
        list [roundFloat [r hincrbyfloat smallhash tmp 2.5]] \
             [roundFloat [r hincrbyfloat bighash tmp 2.5]]
    } {102.5 102.5}

    test {HINCRBYFLOAT over 32bit value} {
        r hset smallhash tmp 17179869184
        r hset bighash tmp 17179869184
        list [r hincrbyfloat smallhash tmp 1] \
             [r hincrbyfloat bighash tmp 1]
    } {17179869185 17179869185}

    test {HINCRBYFLOAT over 32bit value with over 32bit increment} {
        r hset smallhash tmp 17179869184
        r hset bighash tmp 17179869184
        list [r hincrbyfloat smallhash tmp 17179869184] \
             [r hincrbyfloat bighash tmp 17179869184]
    } {34359738368 34359738368}

    test {HINCRBYFLOAT fails against hash value with spaces (left)} {
        r hset smallhash str " 11"
        r hset bighash str " 11"
        catch {r hincrbyfloat smallhash str 1} smallerr
        catch {r hincrbyfloat bighash str 1} bigerr
        set rv {}
        lappend rv [string match "ERR*not*float*" $smallerr]
        lappend rv [string match "ERR*not*float*" $bigerr]
    } {1 1}

    test {HINCRBYFLOAT fails against hash value with spaces (right)} {
        r hset smallhash str "11 "
        r hset bighash str "11 "
        catch {r hincrbyfloat smallhash str 1} smallerr
        catch {r hincrbyfloat bighash str 1} bigerr
        set rv {}
        lappend rv [string match "ERR*not*float*" $smallerr]
        lappend rv [string match "ERR*not*float*" $bigerr]
    } {1 1}

    test {HINCRBYFLOAT fails against hash value that contains a null-terminator in the middle} {
        r hset h f "1\x002"
        catch {r hincrbyfloat h f 1} err
        set rv {}
        lappend rv [string match "ERR*not*float*" $err]
    } {1}

    test {HSTRLEN against the small hash} {
        set err {}
        foreach k [array names smallhash *] {
            if {[string length $smallhash($k)] ne [r hstrlen smallhash $k]} {
                set err "[string length $smallhash($k)] != [r hstrlen smallhash $k]"
                break
            }
        }
        set _ $err
    } {}

    test {HSTRLEN against the big hash} {
        set err {}
        foreach k [array names bighash *] {
            if {[string length $bighash($k)] ne [r hstrlen bighash $k]} {
                set err "[string length $bighash($k)] != [r hstrlen bighash $k]"
                puts "HSTRLEN and logical length mismatch:"
                puts "key: $k"
                puts "Logical content: $bighash($k)"
                puts "Server  content: [r hget bighash $k]"
            }
        }
        set _ $err
    } {}

    test {HSTRLEN against non existing field} {
        set rv {}
        lappend rv [r hstrlen smallhash __123123123__]
        lappend rv [r hstrlen bighash __123123123__]
        set _ $rv
    } {0 0}

    test {HSTRLEN corner cases} {
        set vals {
            -9223372036854775808 9223372036854775807 9223372036854775808
            {} 0 -1 x
        }
        foreach v $vals {
            r hmset smallhash field $v
            r hmset bighash field $v
            set len1 [string length $v]
            set len2 [r hstrlen smallhash field]
            set len3 [r hstrlen bighash field]
            assert {$len1 == $len2}
            assert {$len2 == $len3}
        }
    }

    test {Hash ziplist regression test for large keys} {
        r hset hash kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk a
        r hset hash kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk b
        r hget hash kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk
    } {b}

    foreach size {10 512} {
        test "Hash fuzzing #1 - $size fields" {
            for {set times 0} {$times < 10} {incr times} {
                catch {unset hash}
                array set hash {}
                r del hash

                # Create
                for {set j 0} {$j < $size} {incr j} {
                    set field [randomValue]
                    set value [randomValue]
                    r hset hash $field $value
                    set hash($field) $value
                }

                # Verify
                foreach {k v} [array get hash] {
                    assert_equal $v [r hget hash $k]
                }
                assert_equal [array size hash] [r hlen hash]
            }
        }

        test "Hash fuzzing #2 - $size fields" {
            for {set times 0} {$times < 10} {incr times} {
                catch {unset hash}
                array set hash {}
                r del hash

                # Create
                for {set j 0} {$j < $size} {incr j} {
                    randpath {
                        set field [randomValue]
                        set value [randomValue]
                        r hset hash $field $value
                        set hash($field) $value
                    } {
                        set field [randomSignedInt 512]
                        set value [randomSignedInt 512]
                        r hset hash $field $value
                        set hash($field) $value
                    } {
                        randpath {
                            set field [randomValue]
                        } {
                            set field [randomSignedInt 512]
                        }
                        r hdel hash $field
                        unset -nocomplain hash($field)
                    }
                }

                # Verify
                foreach {k v} [array get hash] {
                    assert_equal $v [r hget hash $k]
                }
                assert_equal [array size hash] [r hlen hash]
            }
        }
    }

    test {Stress test the hash ziplist -> hashtable encoding conversion} {
        r config set hash-max-ziplist-entries 32
        for {set j 0} {$j < 100} {incr j} {
            r del myhash
            for {set i 0} {$i < 64} {incr i} {
                r hset myhash [randomValue] [randomValue]
            }
            assert {[r object encoding myhash] eq {hashtable}}
        }
    }

    # The following test can only be executed if we don't use Valgrind, and if
    # we are using x86_64 architecture, because:
    #
    # 1) Valgrind has floating point limitations, no support for 80 bits math.
    # 2) Other archs may have the same limits.
    #
    # 1.23 cannot be represented correctly with 64 bit doubles, so we skip
    # the test, since we are only testing pretty printing here and is not
    # a bug if the program outputs things like 1.299999...
    if {!$::valgrind && [string match *x86_64* [exec uname -a]]} {
        test {Test HINCRBYFLOAT for correct float representation (issue #2846)} {
            r del myhash
            assert {[r hincrbyfloat myhash float 1.23] eq {1.23}}
            assert {[r hincrbyfloat myhash float 0.77] eq {2}}
            assert {[r hincrbyfloat myhash float -0.1] eq {1.9}}
        }
    }

    test {Hash ziplist of various encodings} {
        r del k
        r config set hash-max-ziplist-entries 1000000000
        r config set hash-max-ziplist-value 1000000000
        r hset k ZIP_INT_8B 127
        r hset k ZIP_INT_16B 32767
        r hset k ZIP_INT_32B 2147483647
        r hset k ZIP_INT_64B 9223372036854775808
        r hset k ZIP_INT_IMM_MIN 0
        r hset k ZIP_INT_IMM_MAX 12
        r hset k ZIP_STR_06B [string repeat x 31]
        r hset k ZIP_STR_14B [string repeat x 8191]
        r hset k ZIP_STR_32B [string repeat x 65535]
        set k [r hgetall k]
        set dump [r dump k]

        # will be converted to dict at RESTORE
        r config set hash-max-ziplist-entries 2
        r config set sanitize-dump-payload no
        r restore kk 0 $dump
        set kk [r hgetall kk]

        # make sure the values are right
        assert_equal [lsort $k] [lsort $kk]
        assert_equal [dict get $k ZIP_STR_06B] [string repeat x 31]
        set k [dict remove $k ZIP_STR_06B]
        assert_equal [dict get $k ZIP_STR_14B] [string repeat x 8191]
        set k [dict remove $k ZIP_STR_14B]
        assert_equal [dict get $k ZIP_STR_32B] [string repeat x 65535]
        set k [dict remove $k ZIP_STR_32B]
        set _ $k
    } {ZIP_INT_8B 127 ZIP_INT_16B 32767 ZIP_INT_32B 2147483647 ZIP_INT_64B 9223372036854775808 ZIP_INT_IMM_MIN 0 ZIP_INT_IMM_MAX 12}

    test {Hash ziplist of various encodings - sanitize dump} {
        r config set sanitize-dump-payload yes
        r restore kk 0 $dump replace
        set k [r hgetall k]
        set kk [r hgetall kk]

        # make sure the values are right
        assert_equal [lsort $k] [lsort $kk]
        assert_equal [dict get $k ZIP_STR_06B] [string repeat x 31]
        set k [dict remove $k ZIP_STR_06B]
        assert_equal [dict get $k ZIP_STR_14B] [string repeat x 8191]
        set k [dict remove $k ZIP_STR_14B]
        assert_equal [dict get $k ZIP_STR_32B] [string repeat x 65535]
        set k [dict remove $k ZIP_STR_32B]
        set _ $k
    } {ZIP_INT_8B 127 ZIP_INT_16B 32767 ZIP_INT_32B 2147483647 ZIP_INT_64B 9223372036854775808 ZIP_INT_IMM_MIN 0 ZIP_INT_IMM_MAX 12}

}
