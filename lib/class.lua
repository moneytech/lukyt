local lib = {}

local function readU1(stream)
	return string.byte(stream:read(1))
end

local function readU2(stream)
	return (readU1(stream) << 8) | readU1(stream)
end

local function readU4(stream)
	return (readU2(stream) << 16) | readU2(stream)
end

local function readU1T(str, off)
	return string.byte(str:sub(off,off))
end

local function readU2T(str, off)
	return (readU1T(str, off) << 8) | readU1T(str, off+1)
end

local function readU4T(str, off)
	return (readU2T(str, off) << 16) | readU2T(str, off+2)
end

local function readConstantPools(stream)
	local constantPools = {}
	local cpCount = readU2(stream)
	printDebug(cpCount .. " constants in the constant pool")
	for i=1, cpCount-1 do
		local tag = readU1(stream)
		if tag == 11 then -- CONSTANT_InterfaceMethodRef
			local classIndex = readU2(stream)
			local natIndex = readU2(stream)
			table.insert(constantPools, {
				type = "interfaceMethodRef",
				nameAndTypeIndex = natIndex,
				classIndex = classIndex
			})
		end
		if tag == 10 then -- CONSTANT_Methodref
			local classIndex = readU2(stream)
			local natIndex = readU2(stream)
			table.insert(constantPools, {
				type = "methodRef",
				nameAndTypeIndex = natIndex,
				classIndex = classIndex
			})
		end
		if tag == 9 then -- CONSTANT_Fieldref
			local classIndex = readU2(stream)
			local natIndex = readU2(stream)
			table.insert(constantPools, {
				type = "fieldRef",
				nameAndTypeIndex = natIndex,
				classIndex = classIndex
			})
		end
		if tag == 8 then -- CONSTANT_String_info
			local stringIndex = readU2(stream)
			table.insert(constantPools, {
				type = "string",
				textIndex = stringIndex
			})
		end
		if tag == 3 then -- CONSTANT_Integer
			local int = readU4(stream)
			table.insert(constantPools, {
				type = "integer",
				value = int
			})
		end
		if tag == 4 then -- CONSTANT_Float
			local bytes = stream:read(4)
		end
		if tag == 5 then -- CONSTANT_Long
			local highBytes = readU4(stream)
			local lowBytes = readU4(stream)
			table.insert(constantPools, {
				type = "long",
				highBytes = highBytes,
				lowBytes = lowBytes
			})
		end
		if tag == 6 then -- CONSTANT_Double
			local highBytes = stream:read(4)
			local lowBytes = stream:read(4)
			table.insert(constantPools, {
				type = "double",
				highBytes = highBytes,
				lowBytes = lowBytes
			})
		end
		if tag == 12 then -- CONSTANT_NameAndType
			local nameIndex = readU2(stream)
			local descriptorIndex = readU2(stream)
			table.insert(constantPools, {
				type = "nameAndType",
				nameIndex = nameIndex,
				descriptorIndex = descriptorIndex
			})
		end
		if tag == 1 then -- CONSTANT_Utf8
			local length = readU2(stream)
			local bytes = stream:read(length)
			table.insert(constantPools, {
				type = "utf8",
				text = bytes
			})
		end
		if tag == 15 then -- CONSTANT_MethodHandle
			local referenceKind = readU1(stream)
			local referenceIndex = readU2(stream)

		end
		if tag == 16 then -- CONSTANT_MethodType
			local descriptorIndex = readU2(stream)
			table.insert(constantPools, {
				type = "methodType",
				descriptorIndex = descriptorIndex
			})
		end
		if tag == 18 then -- CONSTANT_InvokeDynamic
			local bootstrapMethodAttrIndex = readU2(stream)
			local natIndex = readU2(stream)
			table.insert(constantPools, {
				type = "invokeDynamic",
				bootstrapMethodAttrIndex = bootstrapMethodAttrIndex,
				nameAndTypeIndex = natIndex
			})
		end
		if tag == 7 then -- CONSTANT_Class
			local nameIndex = readU2(stream)
			table.insert(constantPools, {
				type = "class",
				nameIndex = nameIndex
			})
		end
	end

	for k, v in pairs(constantPools) do
		if v.classIndex then
			v.class = constantPools[v.classIndex]
		end
		if v.nameIndex then
			v.name = constantPools[v.nameIndex]
		end
		if v.descriptorIndex then
			v.descriptor = constantPools[v.descriptorIndex]
		end
		if v.textIndex then
			v.text = constantPools[v.textIndex]
		end
		if v.classIndex then
			v.class = constantPools[v.classIndex]
		end
	end

	return constantPools
end

local function readAttributes(stream, constantPools)
	local attributes = {}
	local attributesCount = readU2(stream)
	for i=1, attributesCount do
		local nameIndex = readU2(stream)
		local length = readU4(stream)
		local bytes = stream:read(length)
		--print("name: " .. constantPools[nameIndex].text .. ", bytes: " .. bytes)
		attributes[constantPools[nameIndex].text] = bytes
	end
	return attributes
end

local function readFields(stream, constantPools)
	local fields = {}
	local fieldsCount = readU2(stream)
	printDebug(fieldsCount .. " fields")
	for i=1, fieldsCount do
		local accessFlags = readU2(stream)
		local nameIndex = readU2(stream)
		local descriptorIndex = readU2(stream)
		local attributes = readAttributes(stream, constantPools)
		table.insert(fields, {
 			accessFlags = accessFlags,
 			name = constantPools[nameIndex].text,
 			descriptor = constantPools[descriptorIndex].text,
 			attributes = attributes
 		})
	end
	return fields
end

local function getMethodCode(method)
	local attr = method.attributes["Code"]
	if not attr then
		error("Invalid method. It doesn't contains any \"Code\" attribute.")
	end
	local maxStack = readU2T(attr, 1)
	local maxLocals = readU2T(attr, 3)
	local codeLength = readU4T(attr, 5)
	printDebug(maxStack .. ", " .. maxLocals .. ", " .. codeLength)
	local code = table.pack(table.unpack(table.pack(attr:byte(1,attr:len())), 9, 8+codeLength))
	-- TODO: exceptions, attribute's attributes
	print("got " .. #code)
	return {
		maxStackSize = maxStack,
		maxLocals = maxLocals,
		code = code
	}
end

local function readMethods(stream, constantPools)
	local methods = {}
	local methodsCount = readU2(stream)
	printDebug(methodsCount .. " methods")
	for i=1, methodsCount do
		local accessFlags = readU2(stream)
		local nameIndex = readU2(stream)
		local descriptorIndex = readU2(stream)
 		local attributes = readAttributes(stream, constantPools)
 		local method = {
 			accessFlags = accessFlags,
 			name = constantPools[nameIndex].text,
 			descriptor = constantPools[descriptorIndex].text,
 			attributes = attributes
 		}
 		method.code = getMethodCode(method)
 		table.insert(methods, method)
	end
	return methods
end

local function getConstantValue(attribute)
	return readU2T(attribute, 1)
end

function lib.read(stream)
	if readU4(stream) ~= 0xCAFEBABE then
		error("invalid signature")
	end
	local minor = readU2(stream)
	local major = readU2(stream)
	printDebug("Class Version: " .. major .. "." .. minor)
	if major > 46 then
		error("unsupported Java version, support only up to 1.2")
	end
	local constantPools = readConstantPools(stream)

	local accessFlags = readU2(stream)
	local this = readU2(stream)
	printDebug("This class: " .. constantPools[this].name.text)
	local super = readU2(stream)
	printDebug("Super class: " .. constantPools[super].name.text)
	printDebug("--- Details ---")
	local interfacesCount = readU2(stream)
	printDebug(interfacesCount .. " interfaces")

	local fields = readFields(stream, constantPools)
	printDebug("--- Class Methods --- ")
	local methods = readMethods(stream, constantPools)
	for _, v in pairs(methods) do
		printDebug(v.name .. ": " .. v.descriptor)
		printDebug("Code: " .. table.concat(v.code.code, ","))
		printDebug("-------")
	end
	local attributes = readAttributes(stream, constantPools)
	return {
		version = minor .. "." .. major,
		constantPool = constantPools,
		accessFlags = accessFlags,
		name = constantPools[this].name.text,
		superClass = constantPools[this].name.text,
		interfaces = {}, -- TODO
		fields = fields,
		methods = methods,
		attributes = attributes
	}
end

return lib